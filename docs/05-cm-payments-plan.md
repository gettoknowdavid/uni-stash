# Epic 15: Payments, Escrow & Settlement

### Hybrid Model — Buyer's Choice of In-App Payment or Off-App (In-Person) Payment

**Derived from:** `01-cm-trd.md`, `02-cm-epics-list.md`, `03-cm-tickets-list.md`

**Status:** Proposed — not yet started

**Depends on:** Epic 4 (Listings CRUD & State Machine), Epic 3 (Auth), Epic 7 (Schools/Admin)

**Builds on top of, does not replace:** the existing `active → reserved → sold` state machine and its `SELECT ... FOR UPDATE` locking pattern (CM-4.6/4.7)

---

## Table of Contents

1. [Why this epic exists](#1-why-this-epic-exists)
2. [Nigerian regulatory & compliance context](#2-nigerian-regulatory--compliance-context)
3. [Database schema additions](#3-database-schema-additions)
4. [Payment gateway abstraction (multi-provider support)](#4-payment-gateway-abstraction-multi-provider-support)
5. [The payment state machine](#5-the-payment-state-machine)
6. [The settlement state machine](#6-the-settlement-state-machine)
7. [Ticket breakdown](#7-ticket-breakdown)
8. [UI changes required](#8-ui-changes-required)
9. [User stories — the exact end-to-end flow](#9-user-stories--the-exact-end-to-end-flow)
10. [Open questions to resolve before implementation starts](#10-open-questions-to-resolve-before-implementation-starts)

---

## 1. Why this epic exists

UniStash today is a trust-based classifieds board: buyer and seller find each other, agree a price off-platform, meet in person, and the seller taps "mark as sold." There is no payment processing anywhere in the codebase — no `payments` table, no Paystack/Flutterwave/InterSwitch integration, no checkout endpoint.

This epic adds an **optional** in-app payment path alongside the existing off-app path. At the point of reservation, the buyer chooses:

- **Pay in-app** — funds are collected up front, held in escrow by the platform, and released to the seller once the buyer confirms receipt (or after an automatic release window).
- **Arrange in person** — identical to today's flow: chat, meet, exchange cash, seller marks sold.

The existing reservation state machine is the backbone for both paths. Payment does not introduce a parallel listing-status system — it introduces a **payment sub-state** that sits alongside `reserved`, and it is that payment sub-state (not a manual seller tap) that drives the `reserved → sold` transition on the in-app path.

### Design principles carried over from the rest of the codebase

- **Money is never a float.** Reuse the existing `core::money::Money` type (`amount_minor` + `Currency`) for every amount this epic touches — payment amount, platform fee, seller payout, refund amount.
- **State transitions are locked, not trusted.** Every transition in this epic that touches `listings.status` or a new `payments.status` column goes through the same `SELECT ... FOR UPDATE` pattern established in `state_machine.rs`. No "check then write" without a lock.
- **Webhooks are the source of truth for payment state, not client callbacks.** A client-side "payment succeeded" redirect is a UX signal, not a fact. Only a verified webhook (or a server-side status poll as fallback) mutates `payments.status`.
- **No new abstraction layers.** Per TRD §1.2, no repository-trait indirection, no DI container. A `PaymentsRepo` following the exact shape of `ListingsRepo`/`AuthRepo` is enough.
- **AppError stays the single error surface.** Payment failures map to existing `AppError` variants (`BadRequest`, `Conflict`, `Internal`) plus one new variant (`PaymentFailed`) — not a separate payments error type.
- **Payment gateway logic is abstracted behind a trait.** The system supports multiple payment gateways (Paystack, Flutterwave, InterSwitch) via a `PaymentGateway` trait. Each gateway implements the trait. A `payment_gateway` column on the `payments` table records which provider handled each transaction.

---

## 2. Nigerian regulatory & compliance context

This section documents the Nigerian legal and regulatory landscape relevant to this epic. It is written for both human reviewers and LLM agents that will implement this feature — **compliance items are not optional unless explicitly marked as "overkill."**

### 2.1 Regulatory bodies and applicable laws

| Body / Law | Relevance to UniStash |
|---|---|
| **Central Bank of Nigeria (CBN)** | Regulates all payment service providers and payment systems. CBN licensing guidelines, the Payments System Vision 2028, and the 2024 updated framework for digital escrow services apply to platforms holding buyer funds. |
| **Nigerian Financial Intelligence Unit (NFIU)** | Receives Suspicious Transaction Reports (STRs) from all reporting entities. Any platform handling funds is a reporting entity under the Money Laundering (Prevention and Prohibition) Act, 2022 (MLPPA). |
| **Federal Competition and Consumer Protection Commission (FCCPC)** | Enforces consumer protection in e-commerce. Requires clear terms of service, complaint resolution processes, and fair dealing. The Federal Competition and Consumer Protection Act (FCCPA) 2018 applies. |
| **Nigeria Data Protection Commission (NDPC)** | Enforces the Nigeria Data Protection Act (NDPA) 2023. Requires data minimisation, consent, right to erasure, and a Data Protection Impact Assessment (DPIA) for high-risk processing (financial data qualifies). |
| **Federal Inland Revenue Service (FIRs)** | Requires VAT collection on platform fees and income reporting. Platform fees are subject to 7.5% VAT. |

### 2.2 CBN escrow and fund-holding requirements

The CBN's 2024 updated framework for digital escrow services introduced key requirements for platforms holding buyer funds:

1. **Licensing**: Platforms must hold a specific CBN licence (PSSP, Switching, or MMO) **or** operate on top of a licensed payment service provider. **UniStash's approach**: operate through licensed gateways (Paystack, Flutterwave, InterSwitch) which hold the appropriate CBN licences. The platform itself does not need its own CBN payment licence as long as funds flow through a licensed provider's rails.
2. **Segregated accounts**: Client funds must be held in accounts separate from operational finances. **UniStash's approach**: funds are held by the payment gateway in their escrow/split-capture infrastructure, not in UniStash's bank account. The platform never holds raw naira — the gateway does.
3. **Transaction records**: Detailed records of all transactions must be maintained and made available to CBN on request. **UniStash's approach**: the `payments`, `settlements`, and `webhook_events` tables serve as this audit trail (see §3).
4. **Dispute resolution**: A documented, auditable process for handling buyer/seller disagreements. **UniStash's approach**: the `payment_disputes` table and admin resolution workflow (CM-15.8, CM-15.9).

### 2.3 AML/CFT requirements (MLPPA 2022 + CBN 2026 Baseline Standards)

Under the Money Laundering (Prevention and Prohibition) Act, 2022 and CBN's March 2026 Baseline Standards for AML solutions:

1. **KYC tiering**: CBN mandates tiered KYC. UniStash already satisfies Tier 1 (email verification via school domain). For in-app payments, the payment gateway handles its own KYC on the buyer at checkout (card/bank verification). **No additional BVN/NIN collection is needed for MVP** as long as transaction volumes stay within Tier 1 limits (₦50,000 per single transaction, ₦300,000 cumulative balance).
2. **Suspicious Transaction Reporting (STR)**: Must be filed with NFIU for transactions that appear suspicious. **For MVP**: flag transactions where the admin disputes a payment, or where the same buyer/seller pair has multiple disputes. A manual STR filing process (admin exports flagged transactions and submits via the NFIU portal) is sufficient — automated STR integration is overkill.
3. **Transaction monitoring**: Real-time monitoring for patterns indicative of money laundering. **For MVP**: the admin audit log and dispute resolution flow provide a basic audit trail. Automated transaction monitoring is overkill for a campus marketplace at MVP scale.
4. **Record retention**: Transaction records must be kept for **at least 5 years** after the transaction. **UniStash's approach**: never hard-delete payment records; the `payments` and `settlements` tables are append-only (status changes are updates, rows are never deleted). A scheduled job should archive data older than 2 years to cold storage, but never delete it.

### 2.4 Consumer protection (FCCPC / FCCPA)

The FCCPA requires e-commerce platforms to:

1. **Clear terms of service**: Disclose the platform's role, fees, escrow mechanics, and dispute process before a transaction begins. **Action item**: add a "Terms & Fees" link to the payment checkout screen (§8.2).
2. **Fee transparency**: All fees (platform commission, gateway processing fees, VAT) must be disclosed before the buyer confirms payment. **Action item**: the `POST /payments/initiate` response must include a `fee_breakdown` object (§7.3).
3. **Receipt/confirmation**: Buyers must receive a transaction receipt after payment. **Action item**: send an email receipt via Resend on `held_in_escrow` and `released` transitions, and display a transaction summary in-app (§8.4).
4. **Refund timelines**: If a refund is owed, it must be processed within a reasonable timeframe. **Action item**: the auto-release job and dispute resolution should target refund completion within 7 business days. Display expected refund timelines in the dispute UI.
5. **Complaint resolution**: A documented process for complaints. **Action item**: the dispute flow (CM-15.8, CM-15.9) serves this purpose. Additionally, a support contact (email or in-app) should be accessible from the payment screens.

### 2.5 Data protection (NDPA 2023)

The Nigeria Data Protection Act requires:

1. **Lawful basis**: Processing financial data requires consent (buyer explicitly initiates payment) or contract performance (processing payment to fulfil the listing reservation).
2. **Data minimisation**: Only collect what's necessary. The platform does **not** store raw card numbers, bank account numbers, or CVV — the payment gateway handles PCI-DSS compliance. UniStash stores only gateway-specific identifiers (reference codes, recipient codes).
3. **Right to erasure**: Users can request deletion of their data. **For financial records**: the right to erasure does not override legal retention requirements (5-year AML retention). Explain this to users in the privacy policy. Non-financial data (chat history, listings) can be soft-deleted per Epic 8's GDPR approach.
4. **Data Protection Impact Assessment (DPIA)**: Required for high-risk processing. Financial transaction processing qualifies. **Action item**: complete a DPIA before going live with in-app payments. This is a document, not code — but it should be referenced in the project docs.

### 2.6 What's NOT required for MVP (overkill)

The following are real Nigerian regulatory requirements but are **not needed at this stage**:

| Requirement | Why it's overkill for MVP |
|---|---|
| **Own CBN payment licence (PSSP/Switching/MMO)** | UniStash routes payments through licensed gateways (Paystack, Flutterwave, InterSwitch). The platform never touches raw funds — the gateway holds them in escrow and disburses on UniStash's instruction. Operating under a licensed principal is sufficient. |
| **Automated STR filing with NFIU** | A manual process (admin flags, exports, and submits via NFIU portal) is sufficient for campus-scale transaction volumes. |
| **Automated real-time AML transaction monitoring** | Manual admin review of disputes and flagged transactions is sufficient. Build automated monitoring when transaction volume justifies it. |
| **BVN/NIN verification for all users** | CBN's tiered KYC allows transactions up to ₦50,000 without BVN. The payment gateway handles buyer-side KYC at checkout. Seller bank details (for payout) are verified by the gateway's resolve-account endpoint. |
| **ISO 20022 compliance** | This is for inter-bank settlement messaging, not applicable to a marketplace platform. |
| **PAPSS integration** | Pan-African Payment and Settlement System is for cross-border payments. UniStash is domestic (Nigeria-only for MVP). |
| **Full PCI-DSS certification** | The payment gateway handles card data. UniStash never touches raw card numbers. The gateway's PCI-DSS compliance covers the card flow; UniStash just needs to ensure it doesn't inadvertently log or store card data. |
| **VAT registration with FIRS** | Required once revenue exceeds the threshold. At MVP scale with minimal platform fees, this is a "do before scaling" item, not a "do before launch" item. Track this as a business TODO, not a code TODO. |

---

## 3. Database schema additions

New migration: `apps/api/migrations/0010_payments.sql`

```sql
-- 0010_payments.sql
--
-- Payment, escrow, settlement, and dispute tracking for the in-app payment path.
-- The off-app path never touches these tables — a listing sold via in-person
-- exchange has no corresponding payments row, exactly as today.
--
-- Settlements are tracked separately from payments because:
--   1. A payment being "released" from escrow is NOT the same as the money
--      arriving in the seller's bank account. The settlement row tracks the
--      actual disbursement.
--   2. Nigerian AML regulations (MLPPA 2022) require detailed transaction
--      records available for CBN audit. Settlement records prove money flow.
--   3. Manual payout workflows (Path B, CM-15.7) require an admin-reviewable
--      queue of pending disbursements.
--   4. A single settlement might cover multiple payments (batch payouts),
--      and a single payment's settlement might fail and need retry — the
--      settlement table tracks this lifecycle independently.

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

    -- Platform fee taken from the amount before payout (basis points, e.g.
    -- 250 = 2.5%). Stored per-payment so historical fee-rate changes don't
    -- rewrite old settlement math.
    platform_fee_bps    SMALLINT NOT NULL DEFAULT 250,
    platform_fee_amount BIGINT NOT NULL CHECK (platform_fee_amount >= 0),
    payout_amount       BIGINT NOT NULL CHECK (payout_amount >= 0),

    -- Payment gateway identification.
    -- Records which provider handled this transaction, enabling multi-gateway
    -- support (Paystack, Flutterwave, InterSwitch) and future gateway additions.
    payment_gateway     TEXT NOT NULL DEFAULT 'paystack'
        CHECK (payment_gateway IN ('paystack', 'flutterwave', 'interswitch')),

    -- Gateway-specific identifiers. Each gateway has its own reference scheme.
    -- These are nullable — a column is only populated when the relevant gateway
    -- handles the payment.
    gateway_reference   TEXT NOT NULL,   -- our generated reference, sent to the gateway
    gateway_tx_id       TEXT,            -- gateway's transaction id, filled on webhook
    gateway_tx_ref      TEXT,            -- gateway's own reference echoed back

    -- Escrow / settlement state machine (see §5 below).
    status              TEXT NOT NULL DEFAULT 'pending_payment'
        CHECK (status IN (
            'pending_payment',   -- checkout initiated, awaiting gateway callback
            'held_in_escrow',    -- payment confirmed, funds held by platform
            'released',          -- payout sent to seller (settlement initiated)
            'refunded',          -- returned to buyer (dispute or cancellation)
            'failed'             -- payment attempt failed or expired
        )),

    held_at             TIMESTAMPTZ,   -- when status -> held_in_escrow
    released_at         TIMESTAMPTZ,   -- when status -> released
    refunded_at         TIMESTAMPTZ,   -- when status -> refunded
    auto_release_at     TIMESTAMPTZ,   -- held_at + escrow window; job releases at this time
                                       -- if the buyer hasn't confirmed or disputed

    failure_reason      TEXT,

    -- Fee breakdown for consumer protection (FCCPC compliance).
    -- Fees must be disclosed before checkout. Stored per-payment so the receipt
    -- always reflects what the buyer was shown at time of purchase.
    gateway_fee_amount  BIGINT NOT NULL DEFAULT 0 CHECK (gateway_fee_amount >= 0),
    vat_amount          BIGINT NOT NULL DEFAULT 0 CHECK (vat_amount >= 0),

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

-- ============================================================
-- settlements: tracks actual fund disbursement to sellers
-- ============================================================
-- WHY THIS TABLE EXISTS (Nigerian compliance):
--
-- 1. AML audit trail: MLPPA 2022 requires records proving the source and
--    destination of all funds. The `payments` table proves money came IN;
--    `settlements` proves money went OUT to a specific bank account.
--
-- 2. CBN escrow compliance: the 2024 framework requires platforms to
--    maintain detailed transaction records and make them available on
--    request. Settlement records are the proof that escrow funds were
--    disbursed correctly.
--
-- 3. Reconciliation: a finance admin must be able to reconcile total
--    payments received vs. total settlements disbursed vs. platform fees
--    retained. Without a settlements table, there's no record of when
--    (or whether) money actually left the platform.
--
-- 4. Tax compliance: FIRS may require proof of income and disbursement.
--    Settlement records provide the disbursement side of the ledger.
--
-- 5. Failure handling: a gateway transfer can fail (insufficient balance
--    on gateway account, invalid bank details, network error). The
--    settlement table tracks retry attempts and failure reasons.
CREATE TABLE settlements (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
    seller_id           UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- The actual amount disbursed (should match payment.payout_amount for
    -- single-payment settlements; batch settlements are a future concern).
    amount              BIGINT NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),

    -- Disbursement state machine (see §6 below).
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',          -- awaiting admin approval or auto-initiation
            'processing',       -- gateway transfer initiated
            'completed',        -- funds confirmed in seller's bank account
            'failed',           -- gateway transfer failed
            'retrying'          -- failed, scheduled for retry
        )),

    -- Gateway-specific transfer identifiers.
    gateway_transfer_id TEXT,            -- gateway's transfer/withdrawal id
    gateway_response    JSONB,           -- full gateway response for debugging

    -- Failure tracking.
    failure_reason      TEXT,
    retry_count         SMALLINT NOT NULL DEFAULT 0,
    next_retry_at       TIMESTAMPTZ,

    -- Admin workflow fields (for manual payout path, CM-15.7 Path B).
    approved_by         UUID REFERENCES admins(id),
    approved_at         TIMESTAMPTZ,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_settlements_seller ON settlements(seller_id, created_at DESC);
CREATE INDEX idx_settlements_status ON settlements(status);
CREATE INDEX idx_settlements_pending ON settlements(created_at)
    WHERE status = 'pending';

-- ============================================================
-- payment_disputes: buyer or seller flags a held-in-escrow payment
-- ============================================================
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
-- double-release or double-refund. The `gateway` column identifies
-- which provider sent the event, enabling multi-gateway support.
CREATE TABLE webhook_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway         TEXT NOT NULL
        CHECK (gateway IN ('paystack', 'flutterwave', 'interswitch')),
    event_id        TEXT NOT NULL,      -- gateway's event/transaction identifier
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Each gateway's event ids are unique within that gateway, not globally.
    -- A Paystack event_id will never collide with a Flutterwave event_id,
    -- but the unique constraint must be per-gateway to allow both.
    CONSTRAINT unique_gateway_event UNIQUE (gateway, event_id)
);
```

**Extension to `listings`:** no new column is strictly required — `listings.status` still only needs `active | reserved | sold | deleted`. The payment sub-state lives entirely in `payments.status`. A listing is "sold via in-app payment" when `listings.status = 'sold'` AND a `payments` row exists with `status = 'released'`; it's "sold off-app" when `listings.status = 'sold'` and no `payments` row exists (or the row is `refunded`/`failed` from an abandoned attempt).

---

## 4. Payment gateway abstraction (multi-provider support)

### 4.1 Why multi-gateway from day one

Nigeria's payment landscape has three major licensed gateways, each with strengths:

| Gateway | Strengths | CBN Licence |
|---|---|---|
| **Paystack** | Best developer experience, strong NGN card coverage, built-in split payments and transfers | Switching & Processing |
| **Flutterwave** | Widest African coverage, supports more card schemes, strong mobile money integration | Switching & Processing |
| **InterSwitch** | Dominant for Verve cards (most common debit card in Nigeria), deepest bank integrations, strongest POS network | Switching & Processing |

Starting with a trait-based abstraction costs ~2 hours of extra work today but avoids a full rewrite when you want to:
- Add Flutterwave for better international card support
- Add InterSwitch for Verve card coverage
- Switch defaults if a gateway has an outage
- Offer buyer choice of payment method in the future

### 4.2 The `PaymentGateway` trait

```rust
// apps/api/src/core/clients/payment_gateway.rs

use crate::core::money::Money;

/// Unified interface for all payment gateway operations.
/// Each gateway (Paystack, Flutterwave, InterSwitch) implements this trait.
/// The trait is object-safe and stored in AppState as `Arc<dyn PaymentGateway>`.
#[async_trait::async_trait]
pub trait PaymentGateway: Send + Sync {
    /// Human-readable name used in DB columns and logs (e.g., "paystack").
    fn name(&self) -> &'static str;

    /// Initialize a transaction. Returns the URL the buyer should be
    /// redirected to (or shown in a webview) to complete payment.
    async fn initialize_transaction(
        &self,
        amount: Money,
        email: &str,
        reference: &str,
        callback_url: &str,
    ) -> Result<GatewayInitResponse, PaymentGatewayError>;

    /// Verify/check transaction status. Used as a fallback when a webhook
    /// is delayed or lost. Returns the current status from the gateway.
    async fn verify_transaction(
        &self,
        reference: &str,
    ) -> Result<GatewayVerifyResponse, PaymentGatewayError>;

    /// Initiate a transfer/payout to a seller's bank account.
    async fn initiate_transfer(
        &self,
        recipient_code: &str,
        amount: Money,
        reference: &str,
        reason: &str,
    ) -> Result<GatewayTransferResponse, PaymentGatewayError>;

    /// Initiate a refund for a payment.
    async fn initiate_refund(
        &self,
        reference: &str,
        amount: Option<Money>,  // None = full refund
    ) -> Result<GatewayRefundResponse, PaymentGatewayError>;

    /// Verify a webhook signature. Each gateway has its own signing scheme.
    /// Returns true if the signature is valid for the given raw body.
    fn verify_webhook_signature(
        &self,
        raw_body: &[u8],
        signature_header: &str,
    ) -> bool;

    /// Resolve a bank account number to an account name.
    /// Used for seller payout details verification.
    async fn resolve_bank_account(
        &self,
        bank_code: &str,
        account_number: &str,
    ) -> Result<ResolvedAccount, PaymentGatewayError>;

    /// Create a transfer recipient for a seller's bank account.
    async fn create_transfer_recipient(
        &self,
        name: &str,
        bank_code: &str,
        account_number: &str,
    ) -> Result<String, PaymentGatewayError>;  // returns recipient_code
}

#[derive(Debug, Clone)]
pub struct GatewayInitResponse {
    pub authorization_url: String,
    pub reference: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum GatewayTransactionStatus {
    Success,
    Failed,
    Abandoned,
    Reversed,
    Pending,
}

#[derive(Debug, Clone)]
pub struct GatewayVerifyResponse {
    pub status: GatewayTransactionStatus,
    pub gateway_tx_id: Option<String>,
    pub gateway_tx_ref: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GatewayTransferResponse {
    pub transfer_id: String,
    pub status: String,  // "pending", "success", "failed"
}

#[derive(Debug, Clone)]
pub struct GatewayRefundResponse {
    pub refund_id: String,
    pub status: String,
}

#[derive(Debug, Clone)]
pub struct ResolvedAccount {
    pub account_name: String,
    pub account_number: String,
    pub bank_code: String,
}

#[derive(Debug, thiserror::enum_dispatch::From)]  // or manual impl
pub enum PaymentGatewayError {
    #[error("Network error: {0}")]
    Network(String),
    #[error("Authentication failed with gateway")]
    Auth,
    #[error("Invalid request: {0}")]
    BadRequest(String),
    #[error("Gateway returned an unexpected response")]
    UnexpectedResponse,
}
```

### 4.3 Gateway-specific implementations

Each gateway gets its own file implementing `PaymentGateway`:

```
apps/api/src/core/clients/
├── payment_gateway.rs          # trait definition (above)
├── paystack.rs                 # PaystackPaymentGateway impl
├── flutterwave.rs              # FlutterwavePaymentGateway impl (future)
└── interswitch.rs              # InterSwitchPaymentGateway impl (future)
```

**Paystack implementation (`paystack.rs`):**
- Initialize: `POST https://api.paystack.co/transaction/initialize`
- Verify: `GET https://api.paystack.co/transaction/verify/{reference}`
- Transfer: `POST https://api.paystack.co/transfer`
- Refund: `POST https://api.paystack.co/refund`
- Webhook signature: HMAC-SHA512 of raw body using secret key, compared against `x-paystack-signature` header
- Resolve account: `POST https://api.paystack.co/bank/resolve`
- Create recipient: `POST https://api.paystack.co/transferrecipient`

**Flutterwave implementation (`flutterwave.rs`):**
- Initialize: `POST https://api.flutterwave.com/v3/payments`
- Verify: `GET https://api.flutterwave.com/v3/transactions/{id}/verify`
- Transfer: `POST https://api.flutterwave.com/v3/transfers`
- Refund: `POST https://api.flutterwave.com/v3/refunds`
- Webhook signature: SHA-256 hash of secret key + raw body, compared against `verif-hash` header
- Resolve account: `POST https://api.flutterwave.com/v3/accounts/resolve`
- Create recipient: `POST https://api.flutterwave.com/v3/transfer-recipients`

**InterSwitch implementation (`interswitch.rs`):**
- Initialize: `POST /api/v2/payments` (InterSwitch Payment Gateway API)
- Verify: `GET /api/v2/transactions/{reference}`
- Transfer: `POST /api/v2/withdrawals`
- Refund: `POST /api/v2/refunds`
- Webhook signature: HMAC-SHA512 with merchant key, compared against ` hash` header

### 4.4 Gateway selection strategy

For MVP, the gateway is configured at the application level (one default gateway, not per-user or per-transaction):

```rust
// apps/api/src/core/config.rs — additions to Config struct

/// Which payment gateway to use. Defaults to "paystack".
/// Change this env var to switch gateways without code changes.
pub default_payment_gateway: String,  // "paystack" | "flutterwave" | "interswitch"

/// Paystack configuration (only needed if gateway is "paystack")
pub paystack_secret_key: Option<String>,
pub paystack_public_key: Option<String>,
pub paystack_webhook_secret: Option<String>,

/// Flutterwave configuration (only needed if gateway is "flutterwave")
pub flutterwave_secret_key: Option<String>,
pub flutterwave_public_key: Option<String>,
pub flutterwave_webhook_secret: Option<String>,

/// InterSwitch configuration (only needed if gateway is "interswitch")
pub interswitch_merchant_code: Option<String>,
pub interswitch_secret_key: Option<String>,
pub interswitch_webhook_secret: Option<String>,
```

The active gateway is injected into `AppState` at boot:

```rust
// apps/api/src/core/state.rs — additions to AppState

/// The active payment gateway, selected at boot based on config.
/// Shared across all payment handlers via Arc<dyn PaymentGateway>.
pub payment_gateway: Arc<dyn PaymentGateway>,
```

**Future enhancement:** per-buyer gateway selection (show all available gateways, let the buyer choose). This is a UI change, not an architecture change — the trait abstraction already supports it.

---

## 5. The payment state machine

```
                    buyer chooses "Pay in-app" at reserve time
                                    │
                                    ▼
                          pending_payment ──(gateway checkout abandoned/expired)──▶ failed
                                    │
                       (gateway webhook: payment.success, signature verified)
                                    │
                                    ▼
                          held_in_escrow ──(auto-release timer fires, no dispute)──▶ released
                                    │                                                    │
                    (buyer taps "Confirm Receipt")──────────────────────────────────────▶┘
                                    │
                    (buyer or seller opens a dispute)
                                    │
                                    ▼
                              [payment_disputes row, status='open']
                                    │
                       (admin resolves: release / refund / partial)
                                    │
                        ┌───────────┴───────────┐
                        ▼                       ▼
                    released                refunded
```

**Why the lock pattern still applies:** the auto-release background job and a buyer's manual "Confirm Receipt" tap can race exactly the same way `mark-sold` and `unreserve` could race in Epic 4. Both paths lock the `payments` row with `SELECT ... FOR UPDATE`, check `status = 'held_in_escrow'`, then transition — so a job firing at the same instant a buyer confirms cannot double-release funds. This is a direct reuse of the CM-4.6/4.7 pattern, just against `payments` instead of `listings`.

---

## 6. The settlement state machine

```
               payment transitions to 'released'
                          │
                          ▼
                    pending ──(admin approves / auto-initiate)──▶ processing
                          │                                          │
                   (gateway transfer succeeds)──────────────────▶ completed
                          │
                   (gateway transfer fails)
                          │
                          ▼
                       failed ──(retry logic)──▶ retrying ──▶ processing ──▶ ...
                          │
                   (exceeds max retries)
                          │
                          ▼
                    [admin alerted, manual intervention required]
```

**Settlement → Payment relationship:**
- Each `payments` row with `status = 'released'` should have exactly one corresponding `settlements` row (eventually `completed` or `failed` with max retries).
- A `settlements` row is created inside the same transaction that transitions the payment to `released`.
- If the settlement ultimately fails after max retries, the payment status is NOT rolled back (the escrow was legitimately released) — instead, the seller is notified and an admin is alerted. The money is in the gateway's transfer queue; it's not lost, it just needs manual intervention.

---

## 7. Ticket breakdown

### CM-15.1 — Migration `0010_payments.sql`

**Description:** Create `payments`, `settlements`, `payment_disputes`, and `webhook_events` tables exactly as specified in §3.
**Acceptance Criteria:**

- All four tables created with the constraints above
- `idx_payments_one_active_per_listing` partial unique index verified: inserting a second `pending_payment`/`held_in_escrow` row for the same listing fails
- `webhook_events` unique constraint verified: two events with the same `event_id` but different `gateway` values succeed; same `gateway` + `event_id` fails
- `sqlx migrate run` applies cleanly against a fresh DB

---

### CM-15.2 — `PaymentGateway` trait + `PaystackPaymentGateway` implementation

**Description:** Define the `PaymentGateway` trait (§4.2) and implement it for Paystack (§4.3). This is the gateway abstraction layer that enables future Flutterwave/InterSwitch support.
**Acceptance Criteria:**

- `PaymentGateway` trait defined in `apps/api/src/core/clients/payment_gateway.rs` with all methods from §4.2
- `PaystackPaymentGateway` struct implements `PaymentGateway` in `apps/api/src/core/clients/paystack.rs`
- `initialize_transaction` calls `POST https://api.paystack.co/transaction/initialize`, returns the authorization URL
- `verify_transaction` calls `GET /transaction/verify/{reference}`, maps Paystack's response to `GatewayVerifyResponse`
- `initiate_transfer` calls `POST https://api.paystack.co/transfer`
- `initiate_refund` calls `POST https://api.paystack.co/refund`
- `verify_webhook_signature` validates HMAC-SHA512 against `x-paystack-signature` header
- `resolve_bank_account` calls `POST https://api.paystack.co/bank/resolve`
- `create_transfer_recipient` calls `POST https://api/paystack.co/transferrecipient`
- Amounts converted to gateway's expected minor-unit format at the boundary only — internal representation stays `Money` throughout
- Secret key loaded from `Config` (`PAYSTACK_SECRET_KEY`), never logged
- Unit tests use `wiremock` (already a dev-dependency) to stub Paystack responses — no real network calls in tests

**Technical notes:**

- Paystack's NGN amounts are already in kobo (their minor unit matches ours exactly for NGN) — confirm this holds for any other currency this epic supports before assuming a 1:1 mapping.
- Lives at `apps/api/src/core/clients/paystack.rs`.
- `AppState` must be updated to include `payment_gateway: Arc<dyn PaymentGateway>` (§4.4).

---

### CM-15.3 — `POST /api/v1/payments/initiate`

**Description:** Buyer chooses the in-app payment path at reservation time; this endpoint starts a gateway checkout for an already-reserved listing.
**Acceptance Criteria:**

- Requires `AuthUser`; caller must be the `reserved_by` buyer on the listing (403 otherwise)
- Listing must be in `reserved` status (409 otherwise — mirrors the existing state-machine guard style)
- Rejects if an active (`pending_payment`/`held_in_escrow`) payment already exists for this listing (409) — enforced first at the app level for a clean error, backed by the DB partial unique index as the real guarantee
- `payment_gateway` column set to the active gateway's name (from `AppState.payment_gateway.name()`)
- Computes `platform_fee_amount`, `gateway_fee_amount`, `vat_amount`, and `payout_amount` from the listing's `price` and the current fee configuration
- Inserts a `payments` row (`status = 'pending_payment'`), generates a unique `gateway_reference`, calls `gateway.initialize_transaction`
- Returns `{ authorization_url, reference, fee_breakdown }` — the Flutter client opens `authorization_url` in an in-app webview
- **Fee breakdown in response** (FCCPC compliance, §2.4):
  ```json
  {
    "authorization_url": "https://checkout.paystack.com/...",
    "reference": "uni_abc123",
    "fee_breakdown": {
      "item_price": { "amount_minor": 250000, "currency": "NGN" },
      "platform_fee": { "amount_minor": 6250, "currency": "NGN" },
      "gateway_fee": { "amount_minor": 3750, "currency": "NGN" },
      "vat": { "amount_minor": 1500, "currency": "NGN" },
      "total": { "amount_minor": 261500, "currency": "NGN" }
    }
  }
  ```
- A listing with `barter_request` (no price) cannot initiate payment — 400 with a clear message

---

### CM-15.4 — Gateway webhook receiver(s)

**Description:** Single source of truth for payment confirmation. Each gateway has its own webhook endpoint. Verifies the gateway's signature, records the event for idempotency, and drives the `payments` state machine.

**Endpoints:**
- `POST /api/v1/webhooks/paystack` — Paystack webhook receiver
- `POST /api/v1/webhooks/flutterwave` — Flutterwave webhook receiver (future)
- `POST /api/v1/webhooks/interswitch` — InterSwitch webhook receiver (future)

**Shared webhook processing logic** (in a common module, not duplicated per gateway):

```
apps/api/src/features/payments/
├── mod.rs
├── handlers.rs
├── models.rs
├── repo.rs
├── state_machine.rs          # payment state transitions (locked)
├── settlement_machine.rs     # settlement state transitions (locked)
├── webhook_common.rs         # shared webhook processing after signature verification
├── webhook_paystack.rs       # Paystack-specific event parsing → calls webhook_common
├── webhook_flutterwave.rs    # Flutterwave-specific event parsing (future)
└── webhook_interswitch.rs    # InterSwitch-specific event parsing (future)
```

**Acceptance Criteria:**

- Verifies the gateway-specific signature header — requests with an invalid/missing signature are rejected with 401 **before** any DB write
  - Paystack: `x-paystack-signature` (HMAC-SHA512)
  - Flutterwave: `verif-hash` (SHA-256)
  - InterSwitch: ` hash` (HMAC-SHA512)
- Looks up the event by `(gateway, event_id)` in `webhook_events`; if already processed, returns 200 immediately without re-processing (idempotency)
- On `charge.success` / equivalent: locks the `payments` row (`FOR UPDATE`), verifies it's still `pending_payment`, transitions to `held_in_escrow`, sets `held_at = now()` and `auto_release_at = now() + escrow_window`, and — inside the **same transaction** — transitions the listing `reserved → sold` via the existing state-machine helper
- On `charge.failed` / equivalent: transitions the payment to `failed`, listing stays `reserved` (buyer can retry or switch to off-app)
- Endpoint is registered **outside** the standard auth middleware (gateways can't send a JWT) but is not public in the trust sense — the signature check IS the authentication
- Integration test posts a signed fake webhook body and asserts the full state transition, plus a second identical delivery that's a no-op

**Technical notes:** this is this epic's centerpiece ticket, directly analogous to CM-4.6 — budget real test time for concurrent-webhook-delivery and webhook-vs-manual-confirm race scenarios, not just the happy path.

---

### CM-15.5 — `POST /api/v1/payments/{id}/confirm-receipt`

**Description:** Buyer confirms they received the item, releasing escrowed funds to the seller immediately instead of waiting for the auto-release window.
**Acceptance Criteria:**

- Requires `AuthUser`; caller must be the payment's `buyer_id` (403 otherwise)
- Payment must be `held_in_escrow` (409 otherwise — e.g. already released, or a dispute is open)
- Locks the row, transitions to `released`, sets `released_at`
- Creates a `settlements` row (`status = 'pending'`) in the **same transaction**
- Triggers the payout step (CM-15.7)
- If a `payment_disputes` row is `open` for this payment, confirmation is blocked (409) until the dispute resolves — a buyer can't short-circuit an active dispute they raised

---

### CM-15.6 — Auto-release background job

**Description:** Periodic job that releases escrowed funds automatically once `auto_release_at` passes, if no dispute was raised. Mirrors the shape of CM-4.8's stale-reservation job exactly.
**Acceptance Criteria:**

- Runs every few minutes, finds payments where `status = 'held_in_escrow' AND auto_release_at < now()` and no `open` dispute exists
- Uses the same lock-then-check-then-transition pattern as CM-15.5, so it cannot race a concurrent buyer confirmation or dispute-open action
- Creates a `settlements` row in the same transaction as the payment release
- Escrow window is a named constant (`ESCROW_AUTO_RELEASE_HOURS`, suggested default 72h) — long enough for a buyer to receive and inspect an item, short enough that sellers aren't waiting a week for payout
- Task failure on one payment doesn't halt the batch; failures logged via `tracing`

---

### CM-15.7 — Settlement / payout to seller

**Description:** Moves `payout_amount` to the seller once a payment reaches `released`. This is a two-step process: (1) payment transitions to `released` and a `settlements` row is created, (2) the settlement row drives the actual fund transfer.

**Acceptance Criteria (MVP-scoped — Path B recommended first):**

- **Path B (manual, faster to ship — recommended for MVP):**
  - On payment release, insert into `settlements` with `status = 'pending'`
  - Admin reviews pending settlements via `GET /api/v1/admin/settlements` (filterable by status)
  - Admin approves via `POST /api/v1/admin/settlements/{id}/approve`, which:
    - Sets `approved_by`, `approved_at`
    - Calls `gateway.initiate_transfer()` for the seller's recipient code
    - Transitions settlement to `processing`
  - On gateway callback confirming transfer success: settlement → `completed`
  - On gateway callback confirming failure: settlement → `failed` with `failure_reason`
  - Failed settlements can be retried via `POST /api/v1/admin/settlements/{id}/retry`

- **Path A (automated — future enhancement):**
  - Seller has a `gateway_recipient_code` on file (collected via "Payout Details" screen, CM-15.11)
  - On payment release, automatically call `gateway.initiate_transfer()` without admin intervention
  - Transfer failures are logged and surfaced to an admin queue

- **Settlement records must be retained** for at least 5 years (AML compliance, §2.3). No hard-deletes.

---

### CM-15.8 — `POST /api/v1/payments/{id}/dispute`

**Description:** Either party on a held-in-escrow payment can raise a dispute before auto-release.
**Acceptance Criteria:**

- Requires `AuthUser`; caller must be the payment's `buyer_id` or `seller_id` (403 otherwise)
- Payment must be `held_in_escrow` (409 otherwise — can't dispute a released or refunded payment)
- Only one `open` dispute per payment (409 on a second attempt)
- Inserts a `payment_disputes` row; this **blocks** both auto-release (CM-15.6) and manual confirm-receipt (CM-15.5) until resolved

---

### CM-15.9 — Admin dispute resolution endpoints

**Description:** Admin-only review and resolution of open disputes, reusing the `AdminSession`/`can()` permission pattern from Epic 7/10.
**Acceptance Criteria:**

- `GET /api/v1/admin/payment-disputes` (filterable by status) — requires `AdminSession` with a `payments` permission scope
- `POST /api/v1/admin/payment-disputes/{id}/resolve` — body `{ resolution: "release" | "refund" | "partial", amount?: Money, note: String }`
  - `release` → payment `released`, dispute `resolved_release`, settlement row created
  - `refund` → payment `refunded`, triggers a gateway refund call, dispute `resolved_refund`
  - `partial` → splits `payout_amount` between seller and a partial refund to buyer; requires `amount` field; both money movements logged
- Every resolution writes an `admin_audit_log` row (table already exists from Epic 7/`0005_admins.sql`) — reuse it, don't create a parallel audit table

---

### CM-15.10 — Refund handling

**Description:** Wraps the gateway's Refund API for the `refunded` transition, whether triggered by dispute resolution or a pre-escrow buyer cancellation.
**Acceptance Criteria:**

- `POST /api/v1/payments/{id}/cancel` — buyer can cancel a `pending_payment` (before gateway confirms) with no refund needed (nothing was captured), or request cancellation of a `held_in_escrow` payment, which routes to a dispute rather than an instant refund (prevents buyers unilaterally reversing a completed exchange)
- Refund calls to the gateway are idempotent by reference; our side records the refund attempt and its result before considering the local `refunded` transition final
- **Refund timeline disclosure** (FCCPC compliance, §2.4): the response and UI must state the expected refund timeline (e.g., "Refund will be processed within 7 business days")

---

### CM-15.11 — Seller payout details collection (if Path A chosen in CM-15.7)

**Description:** One-time settings screen where a seller provides bank details, converted to a gateway Transfer Recipient.
**Acceptance Criteria:**

- `POST /api/v1/users/me/payout-details` — bank code + account number, validated against the gateway's "resolve account number" endpoint before saving (confirms the account name matches, catches typos)
- Stored as `gateway_recipient_code` only — raw account numbers are never persisted after the recipient is created, mirroring the "never store what you don't need" posture already used for refresh tokens (hash-only) elsewhere in this codebase
- A seller with no payout details on file cannot have their listing's payment auto-released to a real payout — CM-15.7's payout step checks for this and holds/flags instead of failing silently

---

### CM-15.12 — Transaction receipts & email notifications

**Description:** Send email receipts on key payment state changes, as required by FCCPC consumer protection rules (§2.4).
**Acceptance Criteria:**

- **On `held_in_escrow`:** send buyer a payment confirmation email with fee breakdown, expected auto-release time, and dispute instructions
- **On `released`:** send buyer a "payment released" email and seller a "you've been paid" email with settlement details
- **On `refunded`:** send buyer a refund confirmation email with expected refund timeline
- Emails sent via Resend (already integrated in the codebase for email verification)
- In-app transaction history screen (§8.4) shows the same information as the emails

---

### CM-15.13 — Integration & concurrency test suite

**Description:** The `payments` equivalent of CM-2.4 (constraint verification) and CM-4.6's concurrency test — a dedicated pass proving the money-handling code is provably correct, not just happy-path tested.
**Acceptance Criteria:**

- Concurrent webhook delivery (same event, fired twice simultaneously) results in exactly one state transition
- Concurrent auto-release-job-tick and manual confirm-receipt on the same payment: exactly one wins, the other gets a clean 409/no-op
- `idx_payments_one_active_per_listing` is verified under concurrent `initiate` calls: two simultaneous payment-initiation attempts on the same listing result in exactly one `pending_payment` row
- Full lifecycle test: initiate → webhook confirms → escrow held → confirm-receipt → released → settlement completed, asserting `payout_amount` math is exact at every step (no float drift — this is the money-precision story from `core::money` paying off)
- Settlement failure + retry test: initiate settlement → gateway transfer fails → retry succeeds → settlement completed
- Multi-gateway test: same flow works with a mock Flutterwave gateway, proving the trait abstraction works

---

## 8. UI changes required

### 8.1 Listing detail page (`listing_detail_page.dart`)

**Current:** a single "MESSAGE SELLER" button in the footer.

**Change:** once a listing is `reserved` by the current user (buyer), the footer becomes a two-path choice rather than staying on "message seller":

```
┌─────────────────────────────────────────┐
│  HOW WOULD YOU LIKE TO PAY?              │
│                                           │
│  [ 💳 PAY IN-APP — ₦23,500 ]             │
│  Secure checkout, buyer protection        │
│                                           │
│  [ 🤝 ARRANGE IN PERSON ]                │
│  Chat with seller, pay on pickup          │
└─────────────────────────────────────────┘
```

- Barter-only listings (`barter_request` set, no `price`) skip this entirely and go straight to the existing chat flow — there's nothing to pay.
- This choice only appears to the **reserving buyer**, only while the listing is `reserved` and no payment attempt (or a `failed`/abandoned one) exists yet.

### 8.2 New screen: Payment checkout (webview)

- A thin screen hosting a webview pointed at the gateway `authorization_url` returned by `POST /payments/initiate`.
- On the gateway's redirect back to the app's callback URL, the app calls `GET /payments/{id}` (or polls briefly) to confirm status rather than trusting the redirect URL params alone — the webhook is still the source of truth, this screen just gives the user immediate feedback.
- **Must show fee breakdown** before the buyer confirms payment (FCCPC compliance, §2.4) — this can be rendered client-side from the `fee_breakdown` object returned by `POST /payments/initiate`.
- **Must show "Terms & Fees" link** pointing to a page explaining the platform's escrow process, fees, and dispute resolution (FCCPC compliance, §2.4).
- States: `PROCESSING…` → `PAYMENT CONFIRMED — HELD IN ESCROW` (success) or `PAYMENT FAILED — TRY AGAIN OR ARRANGE IN PERSON` (failure, with a button back to the two-path choice).

### 8.3 New screen/section: Order status (post-payment)

Replaces a bare "sold" badge for in-app-paid listings, on **both** buyer and seller views:

**Buyer view:**

```
PAYMENT STATUS: Held in escrow
Funds will be released to the seller automatically in 2 days,
or as soon as you confirm you've received the item.

[ ✓ CONFIRM I RECEIVED THIS ITEM ]
[ ⚠ REPORT A PROBLEM ]

Transaction ID: uni_abc123
Payment method: Paystack (Card)
Paid: ₦23,500.00 on 15 Sep 2026
```

**Seller view:**

```
PAYMENT STATUS: Held in escrow (buyer has 3 days to confirm)
Payout of ₦22,912.50 (after 2.5% fee) will arrive once released.

Settlement status: Awaiting buyer confirmation
Transaction ID: uni_abc123
```

### 8.4 Transaction history screen (new)

Both buyer and seller need a place to see past payments, their status, and dispute history.

**Buyer transaction history:**

```
TRANSACTION HISTORY

┌──────────────────────────────────────────┐
│ 📱 iPhone 14 Pro                         │
│ Status: Released ✓                       │
│ Paid: ₦235,000 on 15 Sep 2026           │
│ Fee: ₦5,875 (platform) + ₦3,525 (card)  │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ 📚 Calculus Textbook                     │
│ Status: Held in escrow ⏳                │
│ Paid: ₦5,500 on 18 Sep 2026             │
│ Auto-release: 21 Sep 2026                │
└──────────────────────────────────────────┘
```

**Seller transaction history** (adds settlement status):

```
TRANSACTION HISTORY

┌──────────────────────────────────────────┐
│ 📱 iPhone 14 Pro                         │
│ Sale: ₦235,000 | Payout: ₦229,125       │
│ Settlement: Completed ✓ (17 Sep 2026)    │
│ To: ••••4523 (GTBank)                    │
└──────────────────────────────────────────┘
```

### 8.5 Profile / Settings additions

- **"Payout Details"** row under Settings (seller-side) — bank account collection, only relevant once a seller has an in-app-paid sale pending. Should not be forced at signup; prompt it contextually the first time a seller's listing gets an in-app payment offer accepted.
- **"Order History"** — buyer and seller both need a place to see past payments, their status, and (if applicable) dispute history. This is new; today "sold" listings have no dedicated history view beyond the profile stats counts.

### 8.6 Chat / messaging screens (once Epic 8/9 land)

- A system message auto-posted into the chat thread on payment state changes ("Payment held in escrow", "Buyer confirmed receipt — funds released") so both parties have a shared record without needing to leave the conversation.

### 8.7 Admin dashboard (new surface, or extend existing admin screens)

- Dispute queue list + detail/resolution screen, gated behind the existing `AdminSession`/permission pattern already used for schools/categories admin screens.
- **Settlement queue** (if Path B chosen in CM-15.7): list of pending settlements, approve/reject/retry actions.

### 8.8 Mockup/copy corrections

- The existing "Payment Screen" / "Checkout" mockups referenced earlier should be revised to reflect **escrow language**, not a one-shot "pay and done" checkout — buyer protection and the confirm-receipt step are the actual value proposition of going in-app over cash, and the UI should say so explicitly, or there's no reason for a buyer to prefer it.

---

## 9. User stories — the exact end-to-end flow

### Story 1 — Seller lists an item with a price

> **As a** verified student seller,
> **I want to** create a listing with a fixed price,
> **so that** buyers can choose to pay for it in-app.

- Given I'm signed in and email-verified, when I submit a listing with `price` set (not `barter_request`), then the listing is created with `status = active` and is payment-eligible.
- No change from the existing CM-4.1 flow — this story just confirms nothing here requires a new seller-side action at listing-creation time.

---

### Story 2 — Buyer reserves the listing

> **As a** buyer,
> **I want to** reserve a listing I intend to buy,
> **so that** it's held for me while I decide how to pay.

- Given the listing is `active` and isn't mine, when I tap "Reserve," then the existing `POST /listings/{id}/reserve` flow runs unchanged (row-locked, 409 if someone beat me to it).
- Given the reservation succeeds, then I see the new "How would you like to pay?" choice (§8.1).

---

### Story 3 — Buyer chooses in-app payment

> **As a** buyer who has just reserved an item,
> **I want to** pay for it securely in-app,
> **so that** my funds are protected until I actually receive the item.

- Given the listing is `reserved` by me and has a `price`, when I tap "Pay In-App," then I see the fee breakdown (price + platform fee + gateway fee + VAT = total), and the "Terms & Fees" link is visible.
- When I confirm, `POST /payments/initiate` runs, a `payments` row is created (`pending_payment`), and I'm shown the gateway checkout webview.
- Given I complete payment on the gateway's page, when the webhook confirms `charge.success`, then (in one transaction) my payment moves to `held_in_escrow` and the listing moves `reserved → sold`. I receive a payment confirmation email.
- Given I abandon or fail the gateway checkout, when I return to the app, then my payment is `failed`, the listing is still `reserved`, and I'm offered "Try Again" or "Arrange In Person" instead.

---

### Story 4 — Buyer chooses off-app payment (status quo, unchanged)

> **As a** buyer who prefers to pay cash on pickup,
> **I want to** skip in-app payment entirely,
> **so that** I can arrange the exchange directly with the seller.

- Given I tap "Arrange In Person," then I'm taken straight to the existing chat flow with the seller — no `payments` row is ever created.
- Given the exchange happens off-platform, when the seller taps "Mark as Sold," then `POST /listings/{id}/mark-sold` runs exactly as it does today (CM-4.7), unchanged.

---

### Story 5 — Buyer confirms receipt, releasing escrow

> **As a** buyer who paid in-app and received the item,
> **I want to** confirm receipt,
> **so that** the seller gets paid without waiting for the automatic window.

- Given my payment is `held_in_escrow` and no dispute is open, when I tap "Confirm I Received This Item," then `POST /payments/{id}/confirm-receipt` transitions the payment to `released`, creates a settlement row, and queues the seller's payout.
- Given I take no action, when 72 hours pass with no dispute raised, then the auto-release job performs the same transition on my behalf.
- In both cases, the seller receives a "you've been paid" email.

---

### Story 6 — Buyer reports a problem (dispute)

> **As a** buyer who paid in-app but the item wasn't as described (or never arrived),
> **I want to** raise a dispute before funds are released,
> **so that** an admin can review it before the seller is paid.

- Given my payment is `held_in_escrow`, when I tap "Report a Problem" and submit a reason, then `POST /payments/{id}/dispute` opens a `payment_disputes` row and both auto-release and my own "confirm receipt" button are blocked.
- Given the dispute is open, when an admin reviews it, then they can resolve it as a full release to the seller, a full refund to me, or a partial split — and I'm notified of the outcome.
- Given a refund is owed, I'm told the expected timeline (e.g., "Refund will be processed within 7 business days").

---

### Story 7 — Seller receives payout

> **As a** seller who sold an item via in-app payment,
> **I want to** receive my payout once escrow releases,
> **so that** I actually get paid for the sale.

- Given I haven't provided payout details yet, when my first in-app sale reaches `released`, then I'm prompted to add bank details (CM-15.11) before the payout can be sent (Path A), or an admin sees my sale in a manual payout queue (Path B).
- Given my payout details are on file, when a payment I'm the seller on transitions to `released`, then a gateway Transfer for `payout_amount` (price minus platform fee) is initiated automatically (Path A) or queued for admin approval (Path B).
- I receive a "you've been paid" email with the payout amount and expected arrival time.
- If the transfer fails, the admin is alerted and I'm notified — my money is not lost, it's in a retry queue.

---

### Story 8 — Seller sees payment status on their own listing

> **As a** seller with a pending in-app sale,
> **I want to** see the current escrow status,
> **so that** I know when to expect payout and whether the buyer has confirmed.

- Given my listing has an associated `payments` row, when I view the listing (or the new Transaction History screen), then I see its current status (`held_in_escrow` / `released` / `refunded` / dispute state) rendered in plain language, not just a raw enum.
- If a settlement is processing, I see the settlement status too.

---

### Story 9 — Admin resolves a dispute

> **As an** admin,
> **I want to** review open payment disputes and decide the outcome,
> **so that** buyer/seller conflicts are resolved fairly and funds move correctly either way.

- Given there are `open` disputes, when I view the admin dispute queue, then I see the listing, both parties, the amount held, and the dispute reason.
- Given I resolve a dispute as `refund`, then the buyer is refunded via the gateway, the payment moves to `refunded`, and the action is written to `admin_audit_log`.
- Given I resolve as `release`, then the seller's payout proceeds exactly as in Story 7.

---

### Story 10 — Admin manages settlements (Path B)

> **As an** admin,
> **I want to** review pending settlements and approve payouts,
> **so that** sellers receive their money in a controlled, auditable process.

- Given there are pending settlements, when I view the admin settlement queue, then I see the seller's name, payout amount, and the associated listing.
- When I approve a settlement, the gateway transfer is initiated and the settlement moves to `processing`.
- When a transfer fails, I see it in the failed settlements queue and can retry or investigate.

---

## 10. Open questions to resolve before implementation starts

1. **Platform fee rate** — 2.5% is a placeholder in the schema (`platform_fee_bps` default). Needs an actual product decision, and whether it's disclosed to the buyer or seller (or both) before checkout. Note: platform fees are subject to 7.5% VAT — clarify whether VAT is absorbed by the platform or added on top.
2. **Escrow window length** — 72 hours is a starting guess. Too short and buyers can't inspect properly (especially with shipping delays, if this ever extends beyond same-campus pickup); too long and sellers feel like their money is stuck.
3. **Payout path (A vs B in CM-15.7)** — this materially changes scope. Recommend starting with Path B (manual admin payout) for the same reason the original build plan chose to defer Cloud Functions: get the trust/escrow story working end-to-end first, automate settlement once there's real transaction volume to justify the Transfer API integration and its failure-handling surface.
4. **Currency scope** — schema supports the existing `Currency` enum (NGN/USD/EUR/GBP), but each gateway's per-currency behavior (especially Transfers) should be confirmed for anything beyond NGN before assuming multi-currency payments "just work." For MVP, restrict in-app payments to NGN only.
5. **What happens to an in-app payment if a listing is deleted mid-escrow?** The `ON DELETE RESTRICT` on `payments.listing_id` deliberately blocks a hard delete while a payment is in flight — but the product behavior (can a seller even soft-delete a listing with `held_in_escrow` funds against it?) needs an explicit rule, likely: block it, same as the existing "can't edit a non-active listing" restriction.
6. **Transaction limits** — CBN tiered KYC limits (§2.3) may affect maximum listing prices for in-app payment. Should the platform enforce a maximum price for in-app-paid listings (e.g., ₦50,000 for Tier 1 users), or leave this to the gateway to enforce?
7. **Which gateway first?** Paystack is the default choice given existing ecosystem familiarity, but Flutterwave's broader card coverage and InterSwitch's Verve card dominance may be worth considering. Confirm before implementation starts.
8. **DPIA completion** — a Data Protection Impact Assessment (§2.5) must be completed before go-live. This is a document deliverable, not code. Ensure someone owns this before the feature ships.
