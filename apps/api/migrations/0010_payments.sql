-- 0010_payments.sql
--
-- Payment, escrow, dispute tracking, and webhook idempotency for the
-- in-app payment path.
--
-- REGULATORY MODEL (CBN-compliant):
--   The platform NEVER holds buyer funds. Funds are held in escrow by
--   the licensed payment gateway (Flutterwave, which holds a CBN
--   Switching & Processing licence). The platform issues settle/refund
--   instructions to the gateway via API; the gateway moves money to the
--   seller's bank account or back to the buyer.
--
--   This avoids the need for a CBN MMO/PSP licence (₦5B capital
--   requirement) and eliminates co-mingling risk. The `payments` table
--   tracks the platform's view of the escrow state; the gateway is the
--   source of truth for the money itself.
--
-- WHY THERE IS NO SETTLEMENTS TABLE:
--   In the original design (platform-as-custodian), a settlements table
--   tracked money leaving the platform's bank account. In this model,
--   money never enters the platform — the gateway holds it and disburses
--   it on our instruction. Settle/refund lifecycle is tracked as columns
--   on the `payments` table itself. A separate settlements table would
--   duplicate data and add indirection with no compliance benefit.
--
-- The off-app path (in-person cash payment) never touches these tables —
-- a listing sold via in-person exchange has no corresponding payments
-- row, exactly as today.


-- ============================================================
-- payments: one row per in-app payment attempt
-- ============================================================
CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id          UUID NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
    buyer_id            UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    seller_id           UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Money: minor units + currency, mirrors core::money::Money exactly.
    amount              BIGINT NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),

    -- Fee breakdown for consumer protection (FCCPA §2.4).
    -- Fees must be disclosed before checkout. Stored per-payment so the
    -- receipt always reflects what the buyer was shown at time of purchase.
    platform_fee_bps    SMALLINT NOT NULL DEFAULT 250,
    platform_fee_amount BIGINT NOT NULL CHECK (platform_fee_amount >= 0),
    gateway_fee_amount  BIGINT NOT NULL DEFAULT 0 CHECK (gateway_fee_amount >= 0),
    vat_amount          BIGINT NOT NULL DEFAULT 0 CHECK (vat_amount >= 0),
    payout_amount       BIGINT NOT NULL CHECK (payout_amount >= 0),

    -- Payment gateway identification.
    -- Flutterwave is the primary escrow provider (has native escrow API).
    -- Paystack / InterSwitch as alternatives or future additions.
    payment_gateway     TEXT NOT NULL DEFAULT 'flutterwave'
        CHECK (payment_gateway IN ('flutterwave', 'paystack', 'interswitch')),

    -- Gateway-specific identifiers.
    gateway_reference   TEXT NOT NULL,   -- our generated reference, sent to the gateway
    gateway_tx_id       TEXT,            -- gateway's transaction id, filled on webhook
    gateway_tx_ref      TEXT,            -- gateway's own reference echoed back

    -- Escrow state machine.
    -- "held_in_escrow" means the GATEWAY (not the platform) is holding the
    -- funds. The platform issues settle/refund instructions via API.
    status              TEXT NOT NULL DEFAULT 'pending_payment'
        CHECK (status IN (
            'pending_payment',   -- checkout initiated, awaiting gateway callback
            'held_in_escrow',    -- gateway holding funds, awaiting buyer confirmation
            'released',          -- gateway settled funds to seller's bank account
            'refunded',          -- gateway refunded the buyer
            'failed'             -- payment attempt failed or expired
        )),

    held_at             TIMESTAMPTZ,   -- when status -> held_in_escrow
    released_at         TIMESTAMPTZ,   -- when status -> released
    refunded_at         TIMESTAMPTZ,   -- when status -> refunded
    auto_release_at     TIMESTAMPTZ,   -- held_at + escrow window; job calls gateway
                                       -- settle endpoint at this time if buyer hasn't
                                       -- confirmed or disputed

    failure_reason      TEXT,

    -- Settle / refund lifecycle tracking.
    -- When we call the gateway's settle or refund endpoint, we track the
    -- API call lifecycle here. This replaces a separate settlements table:
    -- the money was never in our account, so there's nothing to reconcile
    -- on our side — we just need to know whether the gateway call succeeded.
    settle_status       TEXT NOT NULL DEFAULT 'not_initiated'
        CHECK (settle_status IN (
            'not_initiated',     -- escrow held, settle/refund not yet called
            'settle_called',     -- settle API called, awaiting gateway confirmation
            'settled',           -- gateway confirmed settlement to seller
            'refund_called',     -- refund API called, awaiting gateway confirmation
            'refunded',          -- gateway confirmed refund to buyer
            'settle_failed',     -- settle API call failed, retryable
            'refund_failed'      -- refund API call failed, retryable
        )),
    settle_at           TIMESTAMPTZ,   -- when settle was confirmed
    settle_gateway_ref  TEXT,           -- gateway's settle/transfer reference
    settle_attempts     SMALLINT NOT NULL DEFAULT 0,
    last_settle_error   TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT one_active_payment_per_listing
        CHECK (TRUE)
);

-- A listing can have multiple *historical* payment attempts (e.g. one
-- failed, buyer retries) but only one that's actually in flight.
CREATE UNIQUE INDEX idx_payments_one_active_per_listing
    ON payments (listing_id)
    WHERE status IN ('pending_payment', 'held_in_escrow');

CREATE INDEX idx_payments_buyer ON payments(buyer_id, created_at DESC);
CREATE INDEX idx_payments_seller ON payments(seller_id, created_at DESC);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_gateway ON payments(payment_gateway);
CREATE INDEX idx_payments_auto_release ON payments(auto_release_at)
    WHERE status = 'held_in_escrow';
CREATE INDEX idx_payments_settle_status ON payments(settle_status)
    WHERE settle_status NOT IN ('not_initiated', 'settled', 'refunded');


-- ============================================================
-- payment_disputes: buyer or seller flags a held-in-escrow payment
-- ============================================================
-- Disputes are an internal workflow — they block auto-release and
-- manual confirm-receipt until an admin resolves them. The actual
-- money movement (settle or refund) still goes through the gateway.
CREATE TABLE payment_disputes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id      UUID NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    raised_by       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason          TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'resolved_release', 'resolved_refund', 'resolved_partial')),
    resolved_by     UUID REFERENCES admins(id),
    resolution_note TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMPTZ
);
CREATE INDEX idx_payment_disputes_status ON payment_disputes(status);


-- ============================================================
-- webhook_events: idempotency for all payment gateways
-- ============================================================
-- Each gateway sends webhook events. Duplicate delivery is common.
-- Every processed event is recorded so a duplicate is a no-op, not a
-- double-settle or double-refund. The `gateway` column identifies
-- which provider sent the event, enabling multi-gateway support.
CREATE TABLE webhook_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway         TEXT NOT NULL
        CHECK (gateway IN ('flutterwave', 'paystack', 'interswitch')),
    event_id        TEXT NOT NULL,      -- gateway's event/transaction identifier
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Each gateway's event ids are unique within that gateway, not globally.
    CONSTRAINT unique_gateway_event UNIQUE (gateway, event_id)
);
