# Epic 15: Payments, Escrow & Settlement (Paystack Integration)

### Hybrid Model — Buyer's Choice of In-App (Paystack) or Off-App (In-Person) Payment

**Derived from:** `01-cm-trd.md`, `02-cm-epics-list.md`, `03-cm-tickets-list.md`

**Status:** Proposed — not yet started

**Depends on:** Epic 4 (Listings CRUD & State Machine), Epic 3 (Auth), Epic 7 (Schools/Admin)

**Builds on top of, does not replace:** the existing `active → reserved → sold` state machine and its `SELECT ... FOR UPDATE` locking pattern (CM-4.6/4.7)

---

## 1. Why this epic exists

UniStash today is a trust-based classifieds board: buyer and seller find each other, agree a price off-platform, meet in person, and the seller taps "mark as sold." There is no payment processing anywhere in the codebase — no `payments` table, no Paystack/Flutterwave/Stripe integration, no checkout endpoint.

This epic adds an **optional** in-app payment path alongside the existing off-app path. At the point of reservation, the buyer chooses:

- **Pay in-app (Paystack)** — funds are collected up front, held in escrow by the platform, and released to the seller once the buyer confirms receipt (or after an automatic release window).
- **Arrange in person** — identical to today's flow: chat, meet, exchange cash, seller marks sold.

The existing reservation state machine is the backbone for both paths. Payment does not introduce a parallel listing-status system — it introduces a **payment sub-state** that sits alongside `reserved`, and it is that payment sub-state (not a manual seller tap) that drives the `reserved → sold` transition on the in-app path.

### Design principles carried over from the rest of the codebase

- **Money is never a float.** Reuse the existing `core::money::Money` type (`amount_minor` + `Currency`) for every amount this epic touches — payment amount, platform fee, seller payout, refund amount.
- **State transitions are locked, not trusted.** Every transition in this epic that touches `listings.status` or a new `payments.status` column goes through the same `SELECT ... FOR UPDATE` pattern established in `state_machine.rs`. No "check then write" without a lock.
- **Webhooks are the source of truth for payment state, not client callbacks.** A client-side "payment succeeded" redirect is a UX signal, not a fact. Only a verified Paystack webhook (or a server-side status poll as fallback) mutates `payments.status`.
- **No new abstraction layers.** Per TRD §1.2, no repository-trait indirection, no DI container. A `PaymentsRepo` following the exact shape of `ListingsRepo`/`AuthRepo` is enough.
- **AppError stays the single error surface.** Payment failures map to existing `AppError` variants (`BadRequest`, `Conflict`, `Internal`) plus one new variant (`PaymentFailed`) — not a separate payments error type.

---

## 2. Database schema additions

New migration: `apps/api/migrations/0010_payments.sql`

```sql
-- 0010_payments.sql
--
-- Payment, escrow, and settlement tracking for the in-app (Paystack) path.
-- The off-app path never touches this table — a listing sold via in-person
-- exchange has no corresponding payments row, exactly as today.

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

    -- Paystack identifiers.
    paystack_reference  TEXT NOT NULL UNIQUE,   -- our generated reference, sent to Paystack
    paystack_tx_id      TEXT,                    -- Paystack's transaction id, filled on webhook
    paystack_tx_ref     TEXT,                    -- Paystack's own reference echoed back

    -- Escrow / settlement state machine (see §3 below).
    status              TEXT NOT NULL DEFAULT 'pending_payment'
        CHECK (status IN (
            'pending_payment',   -- checkout initiated, awaiting Paystack callback
            'held_in_escrow',    -- payment confirmed, funds held by platform
            'released',          -- payout sent to seller
            'refunded',          -- returned to buyer (dispute or cancellation)
            'failed'             -- payment attempt failed or expired
        )),

    held_at             TIMESTAMPTZ,   -- when status -> held_in_escrow
    released_at         TIMESTAMPTZ,   -- when status -> released
    refunded_at          TIMESTAMPTZ,  -- when status -> refunded
    auto_release_at     TIMESTAMPTZ,   -- held_at + escrow window; job releases at this time
                                       -- if the buyer hasn't confirmed or disputed

    failure_reason      TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT one_active_payment_per_listing
        -- Only one non-terminal payment can exist per listing at a time.
        -- Enforced via a partial unique index below, not a CHECK (CHECK
        -- can't reference other rows).
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
CREATE INDEX idx_payments_auto_release ON payments(auto_release_at)
    WHERE status = 'held_in_escrow';

-- Disputes: a buyer or seller can flag a held-in-escrow payment before
-- auto-release fires. Reuses the shape of the existing `reports` table
-- deliberately, but kept separate — payment disputes have different
-- resolution actions (refund / release / partial) than content moderation.
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

-- Webhook idempotency: Paystack can and will retry webhook delivery.
-- Every processed event id is recorded so a duplicate delivery is a no-op,
-- not a double-release or double-refund.
CREATE TABLE paystack_webhook_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        TEXT NOT NULL UNIQUE,  -- Paystack's event identifier
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Extension to `listings`:** no new column is strictly required — `listings.status` still only needs `active | reserved | sold | deleted`. The payment sub-state lives entirely in `payments.status`. A listing is "sold via in-app payment" when `listings.status = 'sold'` AND a `payments` row exists with `status = 'released'`; it's "sold off-app" when `listings.status = 'sold'` and no `payments` row exists (or the row is `refunded`/`failed` from an abandoned attempt).

---

## 3. The payment state machine

```
                    buyer chooses "Pay in-app" at reserve time
                                    │
                                    ▼
                          pending_payment ──(Paystack checkout abandoned/expired)──▶ failed
                                    │
                       (Paystack webhook: charge.success, signature verified)
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

## 4. Ticket breakdown

### CM-15.1 — Migration `0010_payments.sql`

**Description:** Create `payments`, `payment_disputes`, and `paystack_webhook_events` tables exactly as specified in §2.
**Acceptance Criteria:**

- All three tables created with the constraints above
- `idx_payments_one_active_per_listing` partial unique index verified: inserting a second `pending_payment`/`held_in_escrow` row for the same listing fails
- `sqlx migrate run` applies cleanly against a fresh DB

---

### CM-15.2 — `core::clients::paystack` — Paystack API client

**Description:** Thin HTTP client wrapping Paystack's Transactions API, mirroring the shape of `core::clients::r2::R2Client`.
**Acceptance Criteria:**

- `initialize_transaction(amount: Money, email: &str, reference: &str, callback_url: &str) -> PaystackInitResponse` — calls `POST https://api.paystack.co/transaction/initialize`, returns the authorization URL the client redirects to
- `verify_transaction(reference: &str) -> PaystackVerifyResponse` — calls `GET /transaction/verify/{reference}`, used as a fallback poll if a webhook is delayed/lost
- Amounts are converted to Paystack's expected minor-unit format at the boundary only — internal representation stays `Money` throughout
- Secret key loaded from `Config` (`PAYSTACK_SECRET_KEY`), never logged
- Unit tests use `wiremock` (already a dev-dependency) to stub Paystack responses — no real network calls in tests

**Technical notes:**

- Paystack's NGN amounts are already in kobo (their minor unit matches ours exactly for NGN) — confirm this holds for any other currency this epic supports before assuming a 1:1 mapping.
- Lives at `apps/api/src/core/clients/paystack.rs`.

---

### CM-15.3 — `POST /api/v1/payments/initiate`

**Description:** Buyer chooses the in-app payment path at reservation time; this endpoint starts a Paystack checkout for an already-reserved listing.
**Acceptance Criteria:**

- Requires `AuthUser`; caller must be the `reserved_by` buyer on the listing (403 otherwise)
- Listing must be in `reserved` status (409 otherwise — mirrors the existing state-machine guard style)
- Rejects if an active (`pending_payment`/`held_in_escrow`) payment already exists for this listing (409) — enforced first at the app level for a clean error, backed by the DB partial unique index as the real guarantee
- Computes `platform_fee_amount` and `payout_amount` from the listing's `price` and the current fee bps
- Inserts a `payments` row (`status = 'pending_payment'`), generates a unique `paystack_reference`, calls `paystack.initialize_transaction`
- Returns `{ authorization_url, reference }` — the Flutter client opens `authorization_url` in an in-app webview
- A listing with `barter_request` (no price) cannot initiate payment — 400 with a clear message

---

### CM-15.4 — `POST /api/v1/payments/webhook` — Paystack webhook receiver

**Description:** The single source of truth for payment confirmation. Verifies Paystack's signature, records the event for idempotency, and drives the `payments` state machine.
**Acceptance Criteria:**

- Verifies the `x-paystack-signature` header (HMAC-SHA512 of the raw body using the Paystack secret key) — requests with an invalid/missing signature are rejected with 401 **before** any DB write
- Looks up the event by Paystack's event id in `paystack_webhook_events`; if already processed, returns 200 immediately without re-processing (idempotency)
- On `charge.success`: locks the `payments` row (`FOR UPDATE`), verifies it's still `pending_payment`, transitions to `held_in_escrow`, sets `held_at = now()` and `auto_release_at = now() + escrow_window`, and — inside the **same transaction** — transitions the listing `reserved → sold` via the existing state-machine helper
- On `charge.failed` / expired: transitions the payment to `failed`, listing stays `reserved` (buyer can retry or switch to off-app)
- Endpoint is registered **outside** the standard auth middleware (Paystack can't send a JWT) but is not public in the trust sense — the signature check IS the authentication
- Integration test posts a signed fake webhook body and asserts the full state transition, plus a second identical delivery that's a no-op

**Technical notes:** this is this epic's centerpiece ticket, directly analogous to CM-4.6 — budget real test time for concurrent-webhook-delivery and webhook-vs-manual-confirm race scenarios, not just the happy path.

---

### CM-15.5 — `POST /api/v1/payments/{id}/confirm-receipt`

**Description:** Buyer confirms they received the item, releasing escrowed funds to the seller immediately instead of waiting for the auto-release window.
**Acceptance Criteria:**

- Requires `AuthUser`; caller must be the payment's `buyer_id` (403 otherwise)
- Payment must be `held_in_escrow` (409 otherwise — e.g. already released, or a dispute is open)
- Locks the row, transitions to `released`, sets `released_at`
- Triggers the payout step (CM-15.7)
- If a `payment_disputes` row is `open` for this payment, confirmation is blocked (409) until the dispute resolves — a buyer can't short-circuit an active dispute they raised

---

### CM-15.6 — Auto-release background job

**Description:** Periodic job that releases escrowed funds automatically once `auto_release_at` passes, if no dispute was raised. Mirrors the shape of CM-4.8's stale-reservation job exactly.
**Acceptance Criteria:**

- Runs every few minutes, finds payments where `status = 'held_in_escrow' AND auto_release_at < now()` and no `open` dispute exists
- Uses the same lock-then-check-then-transition pattern as CM-15.5, so it cannot race a concurrent buyer confirmation or dispute-open action
- Escrow window is a named constant (`ESCROW_AUTO_RELEASE_HOURS`, suggested default 72h) — long enough for a buyer to receive and inspect an item, short enough that sellers aren't waiting a week for payout
- Task failure on one payment doesn't halt the batch; failures logged via `tracing`

---

### CM-15.7 — Payout / settlement to seller

**Description:** Moves `payout_amount` to the seller once a payment reaches `released`. For MVP, this can be a Paystack Transfer to the seller's registered bank account/recipient code, or — if bank-account collection is out of scope for MVP — a manual admin-reviewed payout queue.
**Acceptance Criteria (MVP-scoped, decide which sub-path before starting):**

- **Path A (automated):** Seller has a `paystack_recipient_code` on file (collected once via a "Payout Details" settings screen, CM-15.11). On release, call Paystack's Transfer API with `payout_amount`. Transfer failures are logged and surfaced to an admin queue, not silently swallowed.
- **Path B (manual, faster to ship):** On release, insert into a `pending_payouts` view/table an admin reviews and pays out via Paystack's dashboard directly, marking it settled through an admin endpoint. Less automation, but removes bank-account-collection UX and Transfer-API failure handling from MVP scope.
- Recommendation: ship Path B first (matches the "prove the trust flow, then automate" sequencing already used for the rest of this product), promote to Path A once volume justifies it.

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
  - `release` → payment `released`, dispute `resolved_release`
  - `refund` → payment `refunded`, triggers a Paystack refund call, dispute `resolved_refund`
  - `partial` → splits `payout_amount` between seller and a partial refund to buyer; requires `amount` field; both money movements logged
- Every resolution writes an `admin_audit_log` row (table already exists from Epic 7/`0005_admins.sql`) — reuse it, don't create a parallel audit table

---

### CM-15.10 — Refund handling

**Description:** Wraps Paystack's Refund API for the `refunded` transition, whether triggered by dispute resolution or a pre-escrow buyer cancellation.
**Acceptance Criteria:**

- `POST /api/v1/payments/{id}/cancel` — buyer can cancel a `pending_payment` (before Paystack confirms) with no refund needed (nothing was captured), or request cancellation of a `held_in_escrow` payment, which routes to a dispute rather than an instant refund (prevents buyers unilaterally reversing a completed exchange)
- Refund calls to Paystack are idempotent on their side by reference; our side records the refund attempt and its result before considering the local `refunded` transition final

---

### CM-15.11 — Seller payout details collection (if Path A chosen in CM-15.7)

**Description:** One-time settings screen where a seller provides bank details, converted to a Paystack Transfer Recipient.
**Acceptance Criteria:**

- `POST /api/v1/users/me/payout-details` — bank code + account number, validated against Paystack's "resolve account number" endpoint before saving (confirms the account name matches, catches typos)
- Stored as `paystack_recipient_code` only — raw account numbers are never persisted after the recipient is created, mirroring the "never store what you don't need" posture already used for refresh tokens (hash-only) elsewhere in this codebase
- A seller with no payout details on file cannot have their listing's payment auto-released to a real payout — CM-15.7's payout step checks for this and holds/flags instead of failing silently

---

### CM-15.12 — Integration & concurrency test suite

**Description:** The `payments` equivalent of CM-2.4 (constraint verification) and CM-4.6's concurrency test — a dedicated pass proving the money-handling code is provably correct, not just happy-path tested.
**Acceptance Criteria:**

- Concurrent webhook delivery (same event, fired twice simultaneously) results in exactly one state transition
- Concurrent auto-release-job-tick and manual confirm-receipt on the same payment: exactly one wins, the other gets a clean 409/no-op
- `idx_payments_one_active_per_listing` is verified under concurrent `initiate` calls: two simultaneous payment-initiation attempts on the same listing result in exactly one `pending_payment` row
- Full lifecycle test: initiate → webhook confirms → escrow held → confirm-receipt → released, asserting `payout_amount` math is exact at every step (no float drift — this is the money-precision story from `core::money` paying off)

---

## 5. UI changes required

### 5.1 Listing detail page (`listing_detail_page.dart`)

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

### 5.2 New screen: Payment checkout (webview)

- A thin screen hosting a webview pointed at the Paystack `authorization_url` returned by `POST /payments/initiate`.
- On Paystack's redirect back to the app's callback URL, the app calls `GET /payments/{id}` (or polls briefly) to confirm status rather than trusting the redirect URL params alone — the webhook is still the source of truth, this screen just gives the user immediate feedback.
- States: `PROCESSING…` → `PAYMENT CONFIRMED — HELD IN ESCROW` (success) or `PAYMENT FAILED — TRY AGAIN OR ARRANGE IN PERSON` (failure, with a button back to the two-path choice).

### 5.3 New screen/section: Order status (post-payment)

Replaces a bare "sold" badge for in-app-paid listings, on **both** buyer and seller views:

**Buyer view:**

```
PAYMENT STATUS: Held in escrow
Funds will be released to the seller automatically in 2 days,
or as soon as you confirm you've received the item.

[ ✓ CONFIRM I RECEIVED THIS ITEM ]
[ ⚠ REPORT A PROBLEM ]
```

**Seller view:**

```
PAYMENT STATUS: Held in escrow (buyer has 3 days to confirm)
Payout of ₦22,912.50 (after 2.5% fee) will arrive once released.
```

### 5.4 Profile / Settings additions

- **"Payout Details"** row under Settings (seller-side) — bank account collection, only relevant once a seller has an in-app-paid sale pending. Should not be forced at signup; prompt it contextually the first time a seller's listing gets an in-app payment offer accepted.
- **"Order History"** — buyer and seller both need a place to see past payments, their status, and (if applicable) dispute history. This is new; today "sold" listings have no dedicated history view beyond the profile stats counts.

### 5.5 Chat / messaging screens (once Epic 8/9 land)

- A system message auto-posted into the chat thread on payment state changes ("Payment held in escrow", "Buyer confirmed receipt — funds released") so both parties have a shared record without needing to leave the conversation.

### 5.6 Admin dashboard (new surface, or extend existing admin screens)

- Dispute queue list + detail/resolution screen, gated behind the existing `AdminSession`/permission pattern already used for schools/categories admin screens.

### 5.7 Mockup/copy corrections

- The existing "Payment Screen" / "Checkout" mockups referenced earlier should be revised to reflect **escrow language**, not a one-shot "pay and done" checkout — buyer protection and the confirm-receipt step are the actual value proposition of going in-app over cash, and the UI should say so explicitly, or there's no reason for a buyer to prefer it.

---

## 6. User stories — the exact end-to-end flow

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
- Given the reservation succeeds, then I see the new "How would you like to pay?" choice (§5.1).

---

### Story 3 — Buyer chooses in-app payment

> **As a** buyer who has just reserved an item,
> **I want to** pay for it securely in-app,
> **so that** my funds are protected until I actually receive the item.

- Given the listing is `reserved` by me and has a `price`, when I tap "Pay In-App," then `POST /payments/initiate` runs, a `payments` row is created (`pending_payment`), and I'm shown the Paystack checkout webview.
- Given I complete payment on Paystack's page, when Paystack's webhook confirms `charge.success`, then (in one transaction) my payment moves to `held_in_escrow` and the listing moves `reserved → sold`.
- Given I abandon or fail the Paystack checkout, when I return to the app, then my payment is `failed`, the listing is still `reserved`, and I'm offered "Try Again" or "Arrange In Person" instead.

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

- Given my payment is `held_in_escrow` and no dispute is open, when I tap "Confirm I Received This Item," then `POST /payments/{id}/confirm-receipt` transitions the payment to `released` and queues the seller's payout.
- Given I take no action, when 72 hours pass with no dispute raised, then the auto-release job performs the same transition on my behalf.

---

### Story 6 — Buyer reports a problem (dispute)

> **As a** buyer who paid in-app but the item wasn't as described (or never arrived),
> **I want to** raise a dispute before funds are released,
> **so that** an admin can review it before the seller is paid.

- Given my payment is `held_in_escrow`, when I tap "Report a Problem" and submit a reason, then `POST /payments/{id}/dispute` opens a `payment_disputes` row and both auto-release and my own "confirm receipt" button are blocked.
- Given the dispute is open, when an admin reviews it, then they can resolve it as a full release to the seller, a full refund to me, or a partial split — and I'm notified of the outcome.

---

### Story 7 — Seller receives payout

> **As a** seller who sold an item via in-app payment,
> **I want to** receive my payout once escrow releases,
> **so that** I actually get paid for the sale.

- Given I haven't provided payout details yet, when my first in-app sale reaches `released`, then I'm prompted to add bank details (CM-15.11) before the payout can be sent (Path A), or an admin sees my sale in a manual payout queue (Path B).
- Given my payout details are on file, when a payment I'm the seller on transitions to `released`, then a Paystack Transfer for `payout_amount` (price minus platform fee) is initiated automatically.

---

### Story 8 — Seller sees payment status on their own listing

> **As a** seller with a pending in-app sale,
> **I want to** see the current escrow status,
> **so that** I know when to expect payout and whether the buyer has confirmed.

- Given my listing has an associated `payments` row, when I view the listing (or a new Order History screen), then I see its current status (`held_in_escrow` / `released` / `refunded` / dispute state) rendered in plain language, not just a raw enum.

---

### Story 9 — Admin resolves a dispute

> **As an** admin,
> **I want to** review open payment disputes and decide the outcome,
> **so that** buyer/seller conflicts are resolved fairly and funds move correctly either way.

- Given there are `open` disputes, when I view the admin dispute queue, then I see the listing, both parties, the amount held, and the dispute reason.
- Given I resolve a dispute as `refund`, then the buyer is refunded via Paystack, the payment moves to `refunded`, and the action is written to `admin_audit_log`.
- Given I resolve as `release`, then the seller's payout proceeds exactly as in Story 7.

---

## 7. Open questions to resolve before implementation starts

1. **Platform fee rate** — 2.5% is a placeholder in the schema (`platform_fee_bps` default). Needs an actual product decision, and whether it's disclosed to the buyer or seller (or both) before checkout.
2. **Escrow window length** — 72 hours is a starting guess. Too short and buyers can't inspect properly (especially with shipping delays, if this ever extends beyond same-campus pickup); too long and sellers feel like their money is stuck.
3. **Payout path (A vs B in CM-15.7)** — this materially changes scope. Recommend starting with Path B (manual admin payout) for the same reason the original build plan chose to defer Cloud Functions: get the trust/escrow story working end-to-end first, automate settlement once there's real transaction volume to justify the Transfer API integration and its failure-handling surface.
4. **Currency scope** — schema supports the existing `Currency` enum (NGN/USD/EUR/GBP), but Paystack's per-currency behavior (especially Transfers) should be confirmed for anything beyond NGN before assuming multi-currency payments "just work."
5. **What happens to an in-app payment if a listing is deleted mid-escrow?** The `ON DELETE RESTRICT` on `payments.listing_id` deliberately blocks a hard delete while a payment is in flight — but the product behavior (can a seller even soft-delete a listing with `held_in_escrow` funds against it?) needs an explicit rule, likely: block it, same as the existing "can't edit a non-active listing" restriction.
