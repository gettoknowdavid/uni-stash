# Campus Marketplace — Epics List

### Derived from `campus-marketplace-trd.md`, Option B (Rust + Actix-Web)

---

## Epic 1: Backend Foundation & Project Scaffolding

**Phase:** 1 (Weeks 1–2)

**Goal:** Establish the monorepo structure, core module, and config/error/logging scaffolding that every later feature depends on.

**Dependencies:** None — this is the starting point.

**Key work:**

- Monorepo layout (`backend/`, `frontend/`, `shared/`, root CI workflow file)
- `core/config.rs` — env-based config via `dotenvy`, fail-fast on boot if required vars are missing
- `core/error.rs` — `thiserror`-derived `AppError` implementing Actix's `ResponseError`, consistent `{ "error": { "code", "message" } }` JSON shape
- `core/db.rs` — `PgPool` setup, migration runner wiring
- `core/state.rs` — `AppState` struct (db, jwt_keys, r2_client, resend_client, ws_registry)
- `tracing` + `tracing-actix-web` structured logging
- First "hello world" deploy to Shuttle.rs to de-risk deployment early

**Expected outcome:** An empty-but-running Actix binary, deployed, with config/error/logging conventions every feature module will reuse. No business logic yet.

---

## Epic 2: Database Schema & Migrations

**Phase:** 1 (Weeks 1–2)

**Goal:** Stand up the full Postgres schema via forward-only `sqlx` migrations.

**Dependencies:** Epic 1 (needs `core/db.rs` and a provisioned Postgres instance — Neon or Supabase Postgres).

**Key work:**

- `0001_init.sql` — extensions (`pgcrypto`, `citext`), `users`, `refresh_tokens`
- `0002_listings.sql` — `categories`, `listing_status` enum, `listings` (with `search_vector` trigger + GIN index), `images`
- `0003` (or combined) — `chats`, `messages`, `reports`
- Constraint verification: `reserved_fields_consistent` CHECK, `unique_thread`, `max_three_images`, FK cascade rules (especially `listings.reserved_by` nulled-not-cascaded)

**Expected outcome:** `sqlx migrate run` produces the complete schema from §3 of the TRD against a real (free-tier) Postgres instance, ready for feature modules to query against.

---

## Epic 3: Authentication & Authorization System

**Phase:** 1 (Weeks 1–2)

**Goal:** Ship the full `/auth` surface with production-grade token security — this is the highest-risk, most security-sensitive epic and gates every authenticated endpoint after it.

**Dependencies:** Epic 1 (error/config/state), Epic 2 (`users`, `refresh_tokens` tables).

**Key work:**

- `core/auth/password.rs` — Argon2id hash/verify, tuned params for free-tier memory budget
- `core/auth/jwt.rs` — RS256 access tokens (10–15 min TTL, `purpose` claim), opaque high-entropy refresh tokens (SHA-256 hashed at rest)
- `core/auth/middleware.rs` — Actix extractor validating signature, expiry, and `purpose` claim
- `features/auth/` — `signup`, `verify-email`, `login`, `refresh` (rotation + reuse/family revocation + `superseded_by` grace window), `logout`, `me`
- School-email domain allow-list check (post-validation, in-handler, config-driven)
- Resend integration for verification emails
- `actix-governor` rate limiting on `/auth/login` and `/auth/signup` (per-IP and per-email)
- Uniform `401` on login failure (no user enumeration)

**Expected outcome:** A user can sign up with a school email, verify it, log in, receive rotating tokens, and be blocked by rate limits/expiry as designed. This is the security backbone every later phase assumes is solid.

---

## Epic 4: Listings CRUD & State Machine

**Phase:** 2 (Week 3)

**Goal:** Core marketplace object — create, browse, edit, and safely transition listing state under concurrency.

**Dependencies:** Epic 3 (auth middleware for protected routes), Epic 2 (`listings`, `categories` tables).

**Key work:**

- `features/listings/` — `handlers.rs`, `models.rs`, `repo.rs`
- `POST /listings`, `PATCH /listings/{id}` (owner + `active`-only), `DELETE /listings/{id}` (soft delete)
- `GET /listings`, `GET /listings/{id}` — cursor-based pagination
- `state_machine.rs` — `reserve`, `mark-sold`, `unreserve` using `SELECT ... FOR UPDATE` row locking (per §4.3)
- Stale-reservation cleanup background task (48-hour auto-unreserve, same locking pattern)
- `validator`-based DTO validation before any DB call

**Expected outcome:** Listings can be created and browsed, and the reserve/sold/unreserve race condition is provably handled at the DB level — this is the centerpiece engineering story of Option B and should be tested explicitly for concurrent-request correctness.

---

## Epic 5: Full-Text Search

**Phase:** 2 (Week 3)

**Goal:** Deliver real search, the concrete upgrade over Option A's client-side text filter.

**Dependencies:** Epic 4 (listings table populated, `search_vector` trigger from Epic 2 already in place).

**Key work:**

- `GET /listings?q=...` using `plainto_tsquery` against `search_vector`, ranked with `ts_rank`
- Verify trigger correctly weights title (A) over description (B) on insert/update

**Expected outcome:** Query-parameter search returns relevance-ranked results, distinct from and better than Option A's basic substring match.

---

## Epic 6: Image Upload Pipeline

**Phase:** 2 (Week 3)

**Goal:** Let sellers attach up to 3 photos per listing without the backend ever proxying image bytes.

**Dependencies:** Epic 4 (listings must exist to attach images to), Cloudflare R2 (or Supabase Storage) provisioned.

**Key work:**

- `features/images/` — `POST /images/presign` (content-type allowlist, max-3 enforcement)
- `POST /images/confirm` (HEAD check against R2, insert into `images` table)
- `DELETE /images/{id}` (owner-only)

**Expected outcome:** Client can request a presigned URL, upload directly to R2, and register the result — listings can now carry real photos end-to-end.

---

## Epic 7: WebSocket Chat Infrastructure

**Phase:** 3 (Week 4)

**Goal:** Build the live connection layer — `ChatServer`/`ChatSession` actor system — that makes real-time messaging possible.

**Dependencies:** Epic 3 (JWT validation pre-upgrade), Epic 4 (chats reference listings/sellers).

**Key work:**

- `features/chats/ws.rs` — `ChatServer` registry (`HashMap<user_id, Vec<Addr<ChatSession>>>`, multi-device support)
- Connect lifecycle: JWT validated before WS upgrade completes
- Heartbeat: 15s ping / 30s pong timeout → deregistration
- Presence tracking (online/offline notification to thread counterparts)
- Disconnect handling and last-session offline marking

**Expected outcome:** A working, reconnect-safe WebSocket layer at `/ws/chats` that correctly tracks who's online, independent of message persistence (next epic).

---

## Epic 8: Chat Persistence & Message Delivery

**Phase:** 3 (Week 4)

**Goal:** Make Postgres the source of truth for messages, with the WebSocket layer as a pure delivery optimization.

**Dependencies:** Epic 7 (actor system must exist to hook persistence into).

**Key work:**

- `features/chats/repo.rs`, `handlers.rs` — `POST /chats` (idempotent thread creation), `GET /chats`, `GET /chats/{id}/messages` (cursor-paginated)
- Message send flow: persist to Postgres first → update `last_message_at` → forward live if recipient connected → else mark undelivered
- Offline delivery / reconnect sync (`delivered_at IS NULL` proactive push or client-initiated `sync`)
- FCM push notification fired server-side when recipient has no active session
- Per-`user_id` rate limiting on message sends (30/min via `actix-governor`)

**Expected outcome:** Chat works correctly whether both users are online, one is offline, or a socket drops mid-conversation — REST history always reflects ground truth.

---

## Epic 9: Reports & Moderation

**Phase:** 3 (Week 4, tail end) or early Phase 5

**Goal:** Minimal moderation surface so flagged content/users can be reviewed.

**Dependencies:** Epic 3 (role-based auth check), Epic 4 (listings to report against).

**Key work:**

- `features/reports/` — submit report endpoint, admin-only review endpoint
- Role check re-reads from DB rather than trusting a JWT claim (per §2.5.1, so demoted admins lose access immediately)

**Expected outcome:** Users can flag listings/users; an admin-role account can review and update report status.

---

## Epic 10: Flutter Client — Core Wiring

**Phase:** 4 (Week 5)

**Goal:** Connect the Flutter app to the REST API with proper state management, mirroring the backend's feature structure.

**Dependencies:** Epics 3–6 (auth, listings, search, images must all be functional against a deployed or local backend).

**Key work:**

- `frontend/lib/core/` — API client, Riverpod providers, theming setup
- `frontend/lib/features/auth/`, `listings/`, `images/`, `categories/` — mirroring backend feature folders 1:1
- `forui` component adoption (per §5 decision)
- Auth token storage/refresh handling client-side

**Expected outcome:** A working Flutter app that can sign up, log in, browse/search/filter listings, create listings with photos, and reserve/sell items — everything except chat.

---

## Epic 11: Flutter Client — Real-Time Chat

**Phase:** 4 (Week 5)

**Goal:** Wire the chat UI to both REST history and the live WebSocket connection.

**Dependencies:** Epic 10 (auth/client foundation), Epics 7–8 (backend chat must be functional).

**Key work:**

- `frontend/lib/features/chats/` — WS-backed Riverpod chat provider
- REST-backed thread list and message history (initial load / pagination)
- Live message handling, reconnect/sync logic matching backend's `sync` protocol
- Push notification handling (FCM client-side registration)

**Expected outcome:** Full 1:1 chat experience in the app, functionally complete against the custom backend.

---

## Epic 12: Hardening, Rate Limiting & Error States

**Phase:** 5 (Week 6)

**Goal:** Close the gap between "functionally complete" and "production-acceptable."

**Dependencies:** Epics 1–11 (touches nearly every prior feature).

**Key work:**

- `actix-governor` limits confirmed across all sensitive endpoints
- Client-side empty/error/loading states across every screen
- Server-side validation edge cases (§2.1 — every mutating endpoint's `422` behavior)
- HSTS header, HTTPS enforcement confirmation in deployed environment

**Expected outcome:** The app behaves predictably under bad input, slow networks, and abuse attempts — not just the happy path.

---

## Epic 13: Load Testing & Deployment Finalization

**Phase:** 5 (Week 6)

**Goal:** Produce real performance numbers and lock in the production deployment pipeline.

**Dependencies:** Epic 12 (system should be hardened before load testing is meaningful).

**Key work:**

- `k6` load test specifically targeting `POST /listings/{id}/reserve` (the highest-contention path, per §7)
- CI: confirm `backend`/`frontend` path-filtered jobs run independently (`cargo fmt`/`clippy`/`test`, `flutter analyze`/`test`)
- CD: `sqlx migrate run` as an explicit, separate deploy step (never silent-on-boot in prod)
- Final Shuttle.rs deploy (Fly.io fallback if free-tier constraints bite)
- Secrets audit — JWT keys, Resend/R2 credentials confirmed as GitHub Actions secrets, never committed

**Expected outcome:** A deployed, load-tested MVP with a documented CI/CD pipeline and a citable number for the reserve-endpoint's behavior under concurrent load — the concrete evidence for the "I handled the race condition" interview story.

---

## Dependency Chain at a Glance

```
Epic 1 (Scaffolding)
  └─▶ Epic 2 (Schema) ──▶ Epic 3 (Auth) ──┬─▶ Epic 4 (Listings + State Machine)
                                            │      ├─▶ Epic 5 (Search)
                                            │      └─▶ Epic 6 (Images)
                                            │
                                            ├─▶ Epic 7 (WS Infra) ──▶ Epic 8 (Chat Persistence)
                                            └─▶ Epic 9 (Reports)

Epics 3–6 ──▶ Epic 10 (Flutter Core)
Epics 7–8, Epic 10 ──▶ Epic 11 (Flutter Chat)

Epics 1–11 ──▶ Epic 12 (Hardening) ──▶ Epic 13 (Load Test & Deploy)
```

A couple of notes worth flagging as you plan sprints: Epic 3 is the real critical-path bottleneck — nearly everything downstream needs working auth, so it's worth treating any slip there as a whole-schedule slip, not a one-week slip. And Epic 9 (Reports) is genuinely low-risk to defer into Phase 5 if Week 4 runs long, since nothing else depends on it.
