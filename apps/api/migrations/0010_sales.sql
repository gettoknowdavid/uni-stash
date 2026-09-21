-- 0010_sales.sql
--
-- Sale history: one row per completed sale, written by the listings state
-- machine inside the same transaction that transitions a listing
-- `reserved -> sold` (or `active -> sold` for a walk-up sale).
--
-- WHY THIS TABLE EXISTS:
--   `listings.reserved_by` is cleared when a listing is marked sold (the
--   `reserved_fields_consistent` CHECK requires it), so buyer identity and
--   the agreed terms would otherwise be lost forever. This table preserves
--   who bought what, for how much (or what barter), enabling "My Purchases"
--   / "My Sales" views and future analytics.
--
-- PAYMENT MODEL NOTE:
--   UniStash MVP has NO in-app payments (see docs/06-cm-mvp-plan-no-payments.md).
--   Buyers pay sellers OFF-APP (cash/transfer at the meetup). The price
--   recorded here is the listing's asking price at sale time; the platform
--   never verifies or processes the actual exchange.

CREATE TABLE sale_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,

    -- Buyer is nullable: a seller may mark an ACTIVE listing as sold to a
    -- walk-up who never reserved it (no reserved_by to capture).
    buyer_id UUID REFERENCES users(id) ON DELETE SET NULL,

    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- Snapshot of the listing's terms at sale time. Mirrors the listings
    -- table's actual DB-level guarantee: neither priced-or-barter nor
    -- positivity is enforced by the listings schema (that's API-layer
    -- validation), so sale_history must not reject rows the API accepted.
    price BIGINT,
    currency CHAR(3) NOT NULL DEFAULT 'NGN' CHECK (currency ~ '^[A-Z]{3}$'),
    barter_request TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sale_history_buyer ON sale_history(buyer_id, created_at DESC);
CREATE INDEX idx_sale_history_seller ON sale_history(seller_id, created_at DESC);
CREATE INDEX idx_sale_history_listing ON sale_history(listing_id);
