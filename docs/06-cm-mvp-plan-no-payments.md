# UniStash MVP Plan — No Payments (Barter + Off-App Payment)

> **Date:** September 21, 2026
> **Status:** Approved
> **Supersedes:** `05-cm-payments-plan.md` (Epic 15 — dropped)
> **Scope:** Backend + mobile implementation plan for the payment-free MVP

---

## Decision recap

- No payment system, no gateway, no escrow. Epic 15 is dropped entirely.
- Listings are **barter-only** or **priced**; for priced listings, buyers pay the seller **off-app** (cash/transfer at meetup).
- The existing `active → reserved → sold` state machine **is** the transaction system. Nothing in `state_machine.rs`, `listings/*`, or `Money` needs removing — money types stay (priced listings still display prices and get recorded in sale history).
- Scope additions: **full in-app chat**, **sale_history**, **minimal reports**, **push notifications via Pusher** behind a provider-agnostic abstraction.

## What the codebase already has

| Area                                                                         | State                                           |
| ---------------------------------------------------------------------------- | ----------------------------------------------- |
| Auth, Listings CRUD + state machine, Images, Schools, Admin                  | Done (backend + mobile)                         |
| Chat/report **DB schema** (`0003_chats.sql`: `chats`, `messages`, `reports`) | **Already migrated** — feature code missing     |
| Payments **migration** `0010_payments.sql`                                   | Removed in Phase 0 (was pending; never applied) |
| Mobile `_ReserveButton`                                                      | Placeholder UI only — not wired to API          |
| `WsRegistry` in `AppState`                                                   | Placeholder (`Arc<Mutex<()>>`)                  |
| Background jobs framework (`core/jobs.rs`)                                   | Done, includes auto-unreserve-stale             |

---

## Phase 0 — Remove payments traces (backend)

1. Delete `apps/api/migrations/0010_payments.sql`; create `0010_sales.sql` in its place (Phase 1). Verify with `sqlx migrate run` on a fresh DB.
2. Docs: delete `docs/05-cm-payments-plan.md`; record the "off-app payment" decision in the TRD/epics docs.
3. Grep-sweep for payment references (docs only; no payment code exists).

## Phase 1 — Backend: sale history

Migration `0010_sales.sql`:

```sql
CREATE TABLE sale_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
    buyer_id UUID REFERENCES users(id) ON DELETE SET NULL,  -- nullable: off-app sales to walk-ups
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    price BIGINT,            -- copied from listing at sale time (null = barter)
    currency CHAR(3) NOT NULL,
    barter_request TEXT,     -- copied when barter sale
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sale_history_buyer ON sale_history(buyer_id, created_at DESC);
CREATE INDEX idx_sale_history_seller ON sale_history(seller_id, created_at DESC);
```

**Refactor `features/listings/state_machine.rs`:**

- `mark_sold` writes a `sale_history` row inside the same transaction, capturing `reserved_by` (or NULL for a walk-up sale) plus the listing's price/barter at that moment.

**Endpoints:** `GET /api/v1/users/me/purchases` and `GET /api/v1/users/me/sales` (cursor-paginated).

## Phase 2 — Backend: chats + realtime

New module `apps/api/src/features/chats/` matching the existing feature shape:

- `POST /api/v1/chats` — idempotent create (one thread per listing+buyer pair; DB unique constraint enforces), auth + email-verified.
- `GET /api/v1/chats` — threads for current user with listing thumbnail, counterpart name, last message preview, unread count.
- `GET /api/v1/chats/{id}/messages` — cursor-paginated history (newest first).
- `POST /api/v1/chats/{id}/messages` — REST send fallback; updates `last_message_at`.
- `POST /api/v1/chats/{id}/read` — mark messages read.
- Access control: only the chat's buyer or seller may read/write (403 otherwise), on every endpoint.

**Realtime — Pusher-first, provider-agnostic:**

- `core/realtime/mod.rs`: `RealtimePublisher` trait (`publish(channel, event, payload)`) + config-driven constructor wired into `AppState`.
- Impl `core/realtime/pusher.rs` (Pusher **Channels** server API; publishes `message.new` / `message.read` on `private-chat-{chat_id}`). Swapping providers later touches only this file.
- `POST /api/v1/realtime/auth` — private-channel subscription auth: validates the requester is a participant of the requested chat channel, then signs the Pusher auth response.
- The `WsRegistry` placeholder in `state.rs` is replaced with `realtime: Arc<dyn RealtimePublisher>`.
- Publish failures: logged via `tracing`, never fail the request (the REST row is the source of truth; clients sync on reconnect).

**Config additions:** `realtime_provider` ("pusher" for MVP), `pusher_app_id`, `pusher_key`, `pusher_secret`, `pusher_cluster` — required when provider = pusher (fail fast at boot).

## Phase 3 — Backend: reports (schema exists, code missing)

- `POST /api/v1/reports` — body `{ listing_id?, reported_user_id?, reason }` (DB CHECK requires one target), auth + email-verified, one open report per (reporter, target).
- `GET /api/v1/admin/reports?status=open`; `POST /api/v1/admin/reports/{id}/resolve` — writes `admin_audit_log`; may soft-delete the listing.

## Phase 4 — Backend: push notifications (Pusher Beams behind abstraction)

- `core/notifications/mod.rs`: `PushSender` trait (`send_to_user(user_id, title, body, data)`); impl `core/notifications/beams.rs`.
- `POST /api/v1/notifications/register-device` — stores the Beams device token per user.
- Triggers: new chat message (recipient), reservation created (seller), listing marked sold (buyer). Fire-and-forget.

## Phase 5 — Backend gaps & tests

- Verify `GET /api/v1/categories` is public (it exists — confirmed).
- Stale-reservation job stays as-is.
- Integration tests: chat CRUD + access control; report submit/resolve; `mark_sold` writes a sale_history row; realtime auth rejects non-participants.

## Phase 6 — Mobile: listings flow completion

- Wire `_ReserveButton` in `listing_detail_page.dart` (currently a dead placeholder): calls `POST /listings/{id}/reserve`; handles 409 with refresh + toast; prompts email verification when required.
- Status-driven footer actions: Reserve / "Awaiting meetup" + Unreserve / Mark as Sold + Unreserve / Edit-Delete.
- "Chat with seller" button (non-owner) → creates/fetches chat, routes to it.
- My Purchases / My Sales lists.
- Report/flag entry point.

## Phase 7 — Mobile: chats feature (new)

- Models: ChatThread, ChatMessage (freezed/json_serializable).
- Data: `chats_api.dart` (retrofit), `chats_repository.dart`, `realtime_client.dart` (Pusher Channels, isolated in one file).
- View models: `chat_threads_view_model.dart`, `chat_view_model.dart`.
- Pages: threads list (bottom-nav "Chat" tab) + real chat page (bubbles, input, upward scroll, connection indicator).
- Push: register device with Beams on login; foreground pushes deep-link to chat.

## Phase 8 — Mobile: reports UI + polish

- Report sheet UI + submission.
- Error/loading/empty pass on chat and sales screens.

---

## Main feature flow — user stories

**Buyer**

1. As a buyer, I can browse/search campus listings and open a detail page.
2. As a buyer, I can **reserve** an active listing so the seller holds it for me (seller is notified).
3. As a buyer, I can **chat** with the seller in-app to agree the price (or barter) and where to meet.
4. As a buyer, I can **pay the seller off-app** (cash/transfer at the meetup) — the app plays no role in the money.
5. As a buyer, I can **unreserve** if I change my mind, and I see the item in **My Purchases** once sold.

**Seller** 6. As a seller, I can list an item as **priced** or **barter-only**. 7. As a seller, I get notified when someone reserves my listing and can **chat** to arrange the meetup. 8. As a seller, after the in-person exchange and off-app payment, I **mark the listing sold** — which records the sale (buyer, price/barter) and notifies the buyer. 9. As a seller, I can **unreserve** a stale reservation myself (plus the system auto-unreserves stale ones).

**Both / Trust** 10. As either party, I can **report** a listing or user; admins review and act. 11. As an admin, I review reports and can dismiss them or take down listings.

## Main flow — arrow chart

```
SELLER: create listing (priced | barter)
        -> listing ACTIVE -> appears in browse/search

BUYER:  browse/search -> listing detail
        -> [RESERVE] -> listing RESERVED (seller notified)
        -> [CHAT] -> chat thread created -> agree price/barter + meetup spot

BUYER + SELLER: meet in person
        -> buyer pays OFF-APP (cash/transfer)  <- or -> barter exchange

SELLER: [MARK AS SOLD]
        -> sale_history recorded (buyer, price/barter)
        -> listing SOLD -> buyer notified -> shows in My Purchases

ALTERNATE EXITS:
  buyer/seller -> [UNRESERVE] -> listing back to ACTIVE
  timeout      -> stale-reservation job -> auto UNRESERVE -> ACTIVE
  either party -> [REPORT] -> admin queue -> resolve (dismiss | takedown)
```

## Build order

| Order | Work                                               | Depends on  |
| ----- | -------------------------------------------------- | ----------- |
| 1     | Phase 0 (remove payments) + Phase 1 (sale_history) | —           |
| 2     | Phase 2 (chats REST + Pusher realtime)             | Phase 0     |
| 3     | Phase 3 (reports) — parallelizable                 | —           |
| 4     | Phase 4 (push)                                     | Phase 2     |
| 5     | Phase 6 (mobile listings actions)                  | —           |
| 6     | Phase 7 (mobile chats)                             | Phases 2, 4 |
| 7     | Phase 8 (reports UI + polish)                      | Phases 3, 7 |

## Notes & suggestions

- **Pusher split:** Channels for realtime chat, Beams for push — both behind small traits (`RealtimePublisher`, `PushSender`), so leaving Pusher later means writing one alternate impl file per trait.
- **Keep `Money` and price fields.** Off-app payment doesn't remove prices from the domain.
- **Sale-history nuance:** a seller can mark sold a reserved listing, or an active listing sold to a walk-up; the nullable `buyer_id` handles both.
- Consider a lightweight **rating** feature post-MVP — reputation is the only trust signal the platform retains without payments.
