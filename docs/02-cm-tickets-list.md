# Campus Marketplace — Ticket List

### Derived from `02-cm-epics-list.md` and `01-cm-trd.md` (Rust + Actix-Web)

Ticket ID scheme: `CM-<epic>.<seq>`. Each epic's tickets are meant to be worked roughly top-to-bottom; dependencies are called out where a ticket needs another ticket (not just another epic) to land first.

---

## Epic 1: Backend Foundation & Project Scaffolding

### CM-1.1 — Monorepo layout & root CI workflow skeleton

**Description:** Create the repo root structure (`apps/api/`, `apps/mobile/`, `shared/`, `.github/workflows/`) so both toolchains have their native, un-nested roots from day one, and stub the CI workflow file that later tickets will fill in.
**Acceptance Criteria:**

- Repo root contains `apps/api/`, `apps/mobile/`, `shared/`, `README.md`, `.github/workflows/ci.yml`
- `apps/api/` initialized as a Cargo binary crate (`cargo init --name uni-stash-be`)
- `apps/mobile/` initialized as a Flutter app (`flutter create .`)
- `shared/openapi.yaml` exists as an empty/stub file with a header comment explaining its purpose
- `ci.yml` contains two job stubs (`backend`, `frontend`) that currently just check out code and print a placeholder — real steps land in CM-13.2
- README documents the monorepo layout and how to run each side locally
  **Technical Implementation Notes:**
- Do not create a Cargo workspace spanning `apps/api/` and `apps/mobile/` — per TRD §1.2, Cargo and Flutter/Dart tooling don't compose into one manifest; keep `apps/api/Cargo.toml` and `apps/mobile/pubspec.yaml` fully independent.
- `.gitignore` at root should cover both `target/` (Rust) and `.dart_tool/`/`build/` (Flutter).

---

### CM-1.2 — `core::config` — env-based config with fail-fast boot

**Description:** Implement typed application configuration loaded from environment variables so the server refuses to boot with a clear error rather than failing mysteriously later when a required var is missing.
**Acceptance Criteria:**

- `Config` struct covers: `database_url`, `jwt_private_key`, `jwt_public_key`, `r2_*` credentials, `resend_api_key`, `allowed_email_domains` (list), `port`, `env` (dev/prod)
- `Config::from_env()` returns a descriptive error naming the specific missing/invalid var
- Missing or malformed required var causes the binary to exit non-zero before `HttpServer::bind` is called
- `.env.example` checked into repo documenting every required var
- Unit test covers at least one "missing required var" failure path
  **Technical Implementation Notes:**
- Use `dotenvy` for local `.env` loading (no-op in prod where real env vars are injected by Shuttle.rs/Fly.io).
- Either hand-roll parsing or use `envy` to deserialize into the `Config` struct; prefer explicit parsing if `envy`'s error messages aren't specific enough for the "fail fast with a clear reason" requirement.
- Lives at `apps/api/src/core/config.rs`.

---

### CM-1.3 — `core::error` — unified `AppError` type

**Description:** Build the single error enum every handler across every feature will return, so all API error responses share one consistent JSON shape and status-code mapping.
**Acceptance Criteria:**

- `AppError` enum covers at minimum: `NotFound`, `BadRequest`, `Conflict`, `Unauthorized`, `Forbidden`, `Validation` (field-level), `Internal`
- Implements Actix's `ResponseError`, producing `{ "error": { "code": "...", "message": "..." } }` with correct HTTP status per variant
- `Internal` variant never leaks internal error detail/strings to the client response body (logs full detail server-side via `tracing`, returns a generic message to the client)
- Unit tests assert correct status code + JSON shape for each variant
  **Technical Implementation Notes:**
- Derive with `thiserror`.
- Implement `From<sqlx::Error>` for `AppError` mapping `RowNotFound` → `NotFound`, unique-constraint violations → `Conflict`, everything else → `Internal`.
- Lives at `apps/api/src/core/error.rs`.

---

### CM-1.4 — `core::db` — Postgres pool & migration runner wiring

**Description:** Set up the `sqlx::PgPool` connection and the migration-running mechanism used at boot in non-prod and as an explicit CI/CD step in prod.
**Acceptance Criteria:**

- `PgPool` constructed from `Config.database_url` with sane pool size defaults for a free-tier DB (small max connections, e.g. 5–10)
- `run_migrations(pool)` function wraps `sqlx::migrate!()`
- In `dev`/`test` env, migrations run automatically on boot; in `prod` env, boot does **not** auto-migrate (per TRD §1.3 — migrations run explicitly as a CI/CD step)
- Connection failure at boot produces a clear fail-fast error, consistent with CM-1.2
  **Technical Implementation Notes:**
- Use `sqlx::postgres::PgPoolOptions`.
- `migrations/` directory lives at `apps/api/migrations/` per the TRD layout — this ticket only wires the runner; schema content is Epic 2.
- Lives at `apps/api/src/core/db.rs`.

---

### CM-1.5 — `core::state` — `AppState` struct

**Description:** Define the shared application state struct injected into every Actix handler, holding the DB pool and all external service clients.
**Acceptance Criteria:**

- `AppState` contains: `db: PgPool`, `jwt_keys` (RS256 keypair holder), `r2_client`, `resend_client`, `ws_registry` (placeholder type until Epic 7)
- `AppState` is constructed once at boot and wrapped in `web::Data` for Actix
- Cloning `AppState` is cheap (uses `Arc`/pool-native cloning, not a deep clone)
  **Technical Implementation Notes:**
- Per TRD §1.2: no DI container, no repository trait abstraction — `PgPool` is cloned directly into state and passed by reference. Keep this simple.
- `ws_registry` field type can be a placeholder (`Arc<Mutex<()>>` or similar) until Epic 7 defines the real `ChatServer` address type — avoid blocking this ticket on chat infra.
- Lives at `apps/api/src/core/state.rs`.

---

### CM-1.6 — Structured logging with `tracing`

**Description:** Wire up request-scoped structured logging so every request is traceable in production logs.
**Acceptance Criteria:**

- `tracing-actix-web` middleware registered on the `App`
- Logs are JSON-formatted in `prod` env, human-readable in `dev` env
- Each request log line includes method, path, status, latency, and a request ID
- Panics inside a handler are logged with full context rather than silently 500-ing
  **Technical Implementation Notes:**
- `tracing_subscriber` with an env-filter driven by `RUST_LOG`.
- Confirm `tracing-actix-web`'s `TracingLogger::default()` middleware ordering (should wrap early in the middleware stack).

---

### CM-1.7 — First deploy to Shuttle.rs ("hello world")

**Description:** Deploy the empty-but-running Actix binary to Shuttle.rs to de-risk deployment mechanics before any feature work depends on it.
**Acceptance Criteria:**

- A `GET /health` endpoint returns `200 { "status": "ok" }`
- Binary deploys successfully to Shuttle.rs free hobby tier
- Deployed URL is reachable and documented in the README
- Deploy process (commands, required Shuttle config/secrets) is documented so it's repeatable
  **Technical Implementation Notes:**
- Add `Shuttle.toml` / `shuttle-runtime` + `shuttle-actix-web` integration per Shuttle's Actix quickstart.
- This ticket intentionally ships **before** DB wiring is exercised end-to-end in prod — the goal is proving the deploy path works, not full functionality.
- Note Fly.io as the documented fallback path (config not required yet, just noted in README per TRD §6).

---

## Epic 2: Database Schema & Migrations

### CM-2.1 — Migration `0001_init.sql` — extensions, `users`, `refresh_tokens`

**Description:** Create the first forward-only migration establishing required Postgres extensions and the two auth-related tables.
**Acceptance Criteria:**

- `pgcrypto` and `citext` extensions enabled
- `users` table matches TRD §3 exactly (columns, types, defaults, `email` as `CITEXT UNIQUE`)
- `refresh_tokens` table matches TRD §3 exactly, including `family_id`, `revoked`, `superseded_by` self-referencing FK, and all three indexes (`user_id`, `family_id`, unique `token_hash`)
- `sqlx migrate run` applies cleanly against a fresh local Postgres instance
- Migration is forward-only (no down-migration expected per project convention)
  **Technical Implementation Notes:**
- Use `sqlx-cli` (`sqlx migrate add init`) to generate the numbered file.
- Double-check extension creation order — `citext` must exist before the `users.email` column type is declared.

---

### CM-2.2 — Migration `0002_listings.sql` — categories, listings, images, search trigger

**Description:** Add the marketplace core tables plus the full-text search trigger infrastructure.
**Acceptance Criteria:**

- `categories`, `listing_status` enum, `listings`, `images` tables match TRD §3 exactly
- `reserved_fields_consistent` CHECK constraint present and verified against both valid states (reserved-with-fields, non-reserved-without-fields)
- `search_vector` trigger (`listings_search_vector_update`) created and fires `BEFORE INSERT OR UPDATE OF title, description`
- GIN index on `search_vector` present
- `max_three_images` unique constraint on `(listing_id, position)` present
- Manual test: inserting a listing populates `search_vector` with title weighted `'A'` and description weighted `'B'`
  **Technical Implementation Notes:**
- Trigger function is `plpgsql`; verify weighting with `SELECT search_vector FROM listings WHERE id = ...` and inspect the `tsvector` output format directly.
- This is a fairly dense migration — keep it as one file per TRD numbering, but consider a scratch script to sanity-check the trigger in isolation before merging.

---

### CM-2.3 — Migration `0003_chats.sql` — chats, messages, reports

**Description:** Add the remaining tables needed for chat and moderation.
**Acceptance Criteria:**

- `chats`, `messages`, `reports` tables match TRD §3 exactly
- `unique_thread` constraint (`listing_id`, `buyer_id`) present and verified (duplicate insert attempt fails as expected)
- `idx_messages_undelivered` partial index (`WHERE delivered_at IS NULL`) present
- `report_target` CHECK constraint present and verified (reject a row with both `listing_id` and `reported_user_id` NULL)
  **Technical Implementation Notes:**
- Confirm cascade behavior matches the TRD's FK summary: all `ON DELETE CASCADE` **except** `listings.reserved_by`, which stays nullable-not-cascaded (already handled in CM-2.2's `listings` definition, but re-verify here since `chats`/`messages` reference `users` too).

---

### CM-2.4 — Constraint & cascade verification test suite

**Description:** Write an integration test suite that exercises every constraint and cascade rule from TRD §3 in one place, so schema regressions are caught automatically rather than discovered later in feature work.
**Acceptance Criteria:**

- Test confirms `listings.reserved_by` is set NULL (not cascaded) when the referencing user is deleted
- Test confirms all other documented FK relationships cascade correctly on parent delete
- Test confirms `max_three_images`, `unique_thread`, `reserved_fields_consistent`, and `report_target` constraints all reject the invalid case and accept the valid case
- Suite runs against an ephemeral Postgres instance (matches the CI approach used later in Epic 13)
  **Technical Implementation Notes:**
- Use `sqlx::test` attribute macro, which spins up an isolated DB per test.
- This ticket depends on CM-2.1–2.3 all being merged; it's the schema epic's "done means provably done" checkpoint before Epic 3 starts building on top of it.

---

## Epic 3: Authentication & Authorization System

### CM-3.1 — `core::auth::password` — Argon2id hash/verify wrapper

**Description:** Implement password hashing and verification tuned for the free-tier deploy target's memory budget.
**Acceptance Criteria:**

- `hash_password(plain: &str) -> Result<String, AppError>` and `verify_password(plain: &str, hash: &str) -> Result<bool, AppError>` implemented
- Uses Argon2id variant specifically (not Argon2i/d)
- Params tuned toward ~19 MiB memory / 2 iterations / 1 parallelism floor per TRD §2.5.1, documented inline with a comment explaining the free-tier constraint driving the choice
- No hand-rolled `==` comparison anywhere — verification goes through `argon2::PasswordHash::verify_password`'s constant-time check
- Unit tests: correct password verifies true, incorrect verifies false, malformed hash returns an error not a panic
  **Technical Implementation Notes:**
- `argon2` crate, `PasswordHasher`/`PasswordVerifier` traits.
- Lives at `apps/api/src/core/auth/password.rs`.

---

### CM-3.2 — `core::auth::jwt` — RS256 access token sign/verify

**Description:** Implement signing and verification of short-lived access tokens using asymmetric RS256 signing.
**Acceptance Criteria:**

- `sign_access_token(user_id, email_verified) -> String` produces a JWT with claims: `sub`, `exp`, `iat`, `purpose: "access"`, `email_verified`
- Token TTL is 10–15 minutes, configurable
- `verify_access_token(token: &str) -> Result<AccessClaims, AppError>` validates signature, expiry, and rejects any token whose `purpose` claim isn't `"access"`
- A `purpose: "email_verify"` token (see CM-3.4) presented to `verify_access_token` is rejected even though signed with the same key
- Private key never logged; unit tests use a test keypair, not real secrets
  **Technical Implementation Notes:**
- `jsonwebtoken` crate with `Algorithm::RS256`.
- Keypair loaded from `Config` (CM-1.2) — generate a local dev keypair via `openssl genrsa` / `openssl rsa -pubout`, documented in `.env.example`.
- Lives at `apps/api/src/core/auth/jwt.rs`.

---

### CM-3.3 — `core::auth::middleware` — Actix extractor for `AuthUser`

**Description:** Build the request extractor that validates the `Authorization: Bearer` header on every protected route and yields a typed `AuthUser`.
**Acceptance Criteria:**

- `AuthUser` extractor implements `FromRequest`, extracting and validating the bearer token via CM-3.2's `verify_access_token`
- Missing or malformed `Authorization` header → `401` via `AppError::Unauthorized`
- Expired token → `401` with a distinguishable error code from "missing header" (useful for client-side refresh-trigger logic)
- Successfully validated requests give handlers access to `user_id` and `email_verified` without re-parsing the token
- Integration test: protected dummy route returns `401` with no token, `200` with a valid token
  **Technical Implementation Notes:**
- This extractor is what every feature module's protected handlers will take as a parameter — keep its public shape stable since Epics 4, 6, 7, 8, 9 all depend on it directly.
- Lives at `apps/api/src/core/auth/middleware.rs`.

---

### CM-3.4 — `POST /auth/signup` + Resend email verification trigger

**Description:** Implement account creation with server-side school-email domain enforcement and an emailed verification link.
**Acceptance Criteria:**

- Request validated via `validator` crate (`email` format, `password` min length 10, `display_name` 1–80 chars) — `422` with field errors on failure
- Domain allow-list check happens **after** `.validate()` succeeds, against `Config.allowed_email_domains` — request rejected with a clear error if the domain doesn't match
- Password hashed via CM-3.1 before storage; row inserted with `email_verified = false`
- A short-lived (30 min) `purpose: "email_verify"` JWT is generated and emailed via Resend containing a verification link
- Duplicate email signup attempt returns `409 Conflict`, not a raw DB constraint error
- Resend failures (e.g. API down) are logged and surfaced as a `500` distinct from a validation failure — signup row is not silently left in a broken state (document the chosen behavior: rollback vs. allow-retry-verification)
  **Technical Implementation Notes:**
- `#[derive(Deserialize, Validate)] struct SignupRequest` exactly as specified in TRD §2.2.
- The email-verify JWT reuses CM-3.2's signing key but a distinct `purpose` claim — do not create a second signing key.
- Resend client lives in `AppState` (CM-1.5); wrap its call in a small `core` or `features/auth` helper so retries/timeouts are handled in one place.

---

### CM-3.5 — `POST /auth/verify-email`

**Description:** Consume the emailed verification token and flip the user's `email_verified` flag.
**Acceptance Criteria:**

- Body `{ "token": "<jwt>" }`; token validated for signature, expiry, and `purpose: "email_verify"` specifically
- On success, sets `email_verified = true` for the corresponding `sub` user
- Expired or already-used-pattern token (if you choose to track single-use) returns a clear `400`/`410`-style error, not a generic `500`
- Re-verifying an already-verified account is idempotent (no error, no duplicate side effects)
  **Technical Implementation Notes:**
- Decide and document whether verify-email tokens are single-use-enforced via a DB flag or rely purely on short expiry — TRD doesn't mandate single-use tracking for this token type (unlike refresh tokens), so expiry-only is an acceptable MVP choice; note the decision in code comments.

---

### CM-3.6 — `POST /auth/login` + per-IP/per-email rate limiting

**Description:** Implement credential-based login issuing the access/refresh token pair, with uniform failure responses and rate limiting.
**Acceptance Criteria:**

- Rejects login if `email_verified = false` with a distinguishable error (client needs to know to prompt "check your email" vs. "wrong password")
- Wrong password and nonexistent email both return an identical generic `401` — no user enumeration via differential messages or timing (verify password check runs even on nonexistent-email path, e.g. against a dummy hash, to avoid a timing oracle)
- Returns `{ access_token, refresh_token, expires_in }` on success
- Refresh token is a new row in `refresh_tokens` per CM-3.7's issuance logic
- `actix-governor` rate limits this endpoint independently per-IP (e.g. 10 req/min) **and** per-email, so neither limit can be routed around by varying the other dimension
  **Technical Implementation Notes:**
- Per TRD §2.5.1 — implement the dummy-hash-comparison trick to keep timing consistent between "user not found" and "wrong password" paths.
- `actix-governor` is IP-keyed by default; per-email keying needs a second governor instance or a custom key extractor reading the parsed request body — confirm `actix-governor` supports body-based keys, or implement a lightweight in-memory/DB-backed per-email counter if not.

---

### CM-3.7 — Refresh token issuance & rotation-on-use

**Description:** Implement `POST /auth/refresh` with single-use rotation, sliding expiry, and the `family_id`/`superseded_by` chain.
**Acceptance Criteria:**

- Refresh token handed to the client is a 256-bit CSPRNG-generated opaque value, never a JWT
- Only the SHA-256 hash of the token is stored in `refresh_tokens.token_hash`
- On successful `/auth/refresh`: the presented token is marked `revoked = true`, a new token is issued sharing the same `family_id`, `superseded_by` on the old row points to the new row's id — all in one DB transaction
- New refresh token's expiry is a fresh 14–30 day window (sliding), not capped by the original issuance time
- Invalid, expired, or unknown token hash → `401`
  **Technical Implementation Notes:**
- Use `rand`'s CSPRNG (`rand::rngs::OsRng` or equivalent) for token generation.
- SHA-256 (not Argon2) is correct here per TRD §2.5.1 rationale — the token is already high-entropy, so the slow KDF used for passwords is unnecessary overhead.
- Wrap issuance + revocation in a single `sqlx` transaction (`pool.begin()...commit()`).

---

### CM-3.8 — Refresh-token reuse detection & family revocation

**Description:** Implement the compromise-response path: detecting reuse of an already-revoked refresh token and revoking its entire token family, with a grace window to absorb legitimate network retries.
**Acceptance Criteria:**

- Presenting a token with `revoked = true` that is **not** the immediately-preceding token in its family (i.e., outside the grace window) triggers revocation of every token sharing that `family_id`
- Presenting the _immediately preceding_ token within a short grace window (a few seconds) is accepted without triggering family revocation — distinguished via the `superseded_by` pointer, not a bare boolean
- After family revocation, all previously-issued access tokens tied to that lineage still expire naturally within their own short TTL (no separate access-token blacklist required, per the stateless-JWT design)
- Integration test simulates: (a) a legitimate rapid-retry duplicate request → succeeds via grace window, (b) a stale/old token reused well after rotation → family revoked, subsequent refresh attempts with any family member fail
  **Technical Implementation Notes:**
- This is the highest-value security ticket in the epic — budget real test-writing time for the two reuse scenarios described in TRD §2.5.1.
- Grace window duration should be a named constant, not a magic number, so it's easy to tune later.

---

### CM-3.9 — `POST /auth/logout` & `GET /auth/me`

**Description:** Implement session termination and the current-user profile lookup.
**Acceptance Criteria:**

- `POST /auth/logout` revokes the presented refresh token by DB write immediately — not merely a client-side token discard
- `GET /auth/me` requires a valid access token (via CM-3.3 extractor) and returns the current user's profile (id, email, display_name, email_verified, role)
- Logout with an already-revoked or unknown token is idempotent (returns success, doesn't error)
  **Technical Implementation Notes:**
- Straightforward once CM-3.3 and CM-3.7's table structure exist — mainly a thin handler + repo query.

---

### CM-3.10 — Scheduled cleanup job for expired refresh tokens

**Description:** Add a periodic background task that deletes refresh token rows past `expires_at`, keeping the table from growing unbounded.
**Acceptance Criteria:**

- A background task runs on an interval (e.g. every few hours) and deletes rows where `expires_at < now()`
- Task failure is logged via `tracing` but does not crash the server
- Not required for correctness (expired tokens are already rejected at auth-check time) — ticket is explicitly about table hygiene, documented as such in code comments
  **Technical Implementation Notes:**
- `actix_rt::spawn` + `tokio::time::interval`, same pattern that will be reused in CM-4.6's stale-reservation cleanup — consider factoring a small shared "periodic task runner" helper if the pattern is identical enough to be worth it, but don't over-engineer for a two-job MVP.

---

## Epic 4: Listings CRUD & State Machine

### CM-4.1 — `features/listings` scaffolding & `POST /listings`

**Description:** Set up the listings feature module and implement listing creation.
**Acceptance Criteria:**

- `features/listings/{mod.rs, handlers.rs, models.rs, repo.rs}` created per TRD §1.2 layout
- `POST /listings` requires auth + `email_verified = true` (checked from the JWT claim, consistent with the "no role trust" pattern used elsewhere)
- Request validated via `validator` before any DB call: title, description, `category_id` (must reference an existing row), price (nullable = barter-only), condition
- New listing inserted with `status = 'active'`, `seller_id` derived from the authenticated user (never trusted from the request body)
- Response returns the full created listing object
  **Technical Implementation Notes:**
- Category FK violation should map to a clean `400`/`422` via `AppError`'s `sqlx::Error` conversion (CM-1.3), not a raw DB error leak.
- Route registration happens in `features/listings/mod.rs`, wired into the app in `lib.rs` per the monorepo convention.

---

### CM-4.2 — `GET /listings` browse/filter with cursor pagination

**Description:** Implement the listing browse endpoint with category/price/status filters and cursor-based pagination.
**Acceptance Criteria:**

- Supports query params: `category`, `min_price`, `max_price`, `status` (defaults to `active` only), `cursor`, `limit`
- Pagination is cursor-based (opaque cursor, not offset), stable under concurrent writes
- Default `limit` and a max enforced `limit` (e.g. cap at 50) to prevent abuse
- Response includes a `next_cursor` (or null if no more results)
  **Technical Implementation Notes:**
- A common cursor approach here: encode `(created_at, id)` of the last row as the opaque cursor, since `created_at` alone isn't unique enough for stable ordering — confirm this against the actual sort order chosen.
- This ticket does **not** include full-text search (`q` param) — that's Epic 5, layered on top once this base query shape exists.

---

### CM-4.3 — `GET /listings/{id}` detail view

**Description:** Implement the single-listing detail endpoint including seller display name, images, and category.
**Acceptance Criteria:**

- Returns listing fields plus joined seller `display_name`, associated `images` (ordered by `position`), and category `label`
- Soft-deleted (`status = 'deleted'`) listings return `404` to non-owners
- Owner can still fetch their own deleted listing (for their "my listings" history view) — confirm this is the desired behavior and document it
  **Technical Implementation Notes:**
- One query with joins, or a small number of queries composed in `repo.rs` — avoid N+1 on images if joining.

---

### CM-4.4 — `PATCH /listings/{id}` edit (owner + active-only)

**Description:** Implement listing edits, restricted to the owning seller and only while the listing is in `active` status.
**Acceptance Criteria:**

- `403` if `seller_id != auth user`
- `409 Conflict` if listing status is not `active` (can't edit a reserved or sold listing)
- Partial update supported (only provided fields change)
- Editing title/description correctly re-fires the `search_vector` trigger (verify via a quick manual/integration check against Epic 2's trigger)
  **Technical Implementation Notes:**
- `validator` runs on whatever fields are present in the patch body before the DB call.

---

### CM-4.5 — `DELETE /listings/{id}` soft delete

**Description:** Implement listing removal as a soft delete, preserving chat/report history integrity.
**Acceptance Criteria:**

- Sets `status = 'deleted'`, does not hard-delete the row
- Only the owning seller can delete (or, if desired, admin role — confirm scope; TRD doesn't explicitly grant this to admins, so default to owner-only unless product decides otherwise)
- Deleted listings are excluded from `GET /listings` default browse results (already covered by CM-4.2's `status` default filter, but verify explicitly here)
- Existing chat threads referencing a deleted listing remain intact and readable
  **Technical Implementation Notes:**
- No new locking concern here — this is a straightforward status update, not a contested transition (unlike reserve/mark-sold/unreserve in CM-4.6).

---

### CM-4.6 — State machine: `reserve` transactional endpoint

**Description:** Implement `POST /listings/{id}/reserve` using `SELECT ... FOR UPDATE` row locking to eliminate the TOCTOU race between concurrent reserve attempts.
**Acceptance Criteria:**

- Implementation matches TRD §4.3 exactly: lock row via `FOR UPDATE` inside a transaction, verify `status == Active`, verify buyer isn't the seller, transition to `reserved` with `reserved_by`/`reserved_at` set, commit
- A concurrent second reserve attempt on the same listing (fired near-simultaneously) reliably receives `409 Conflict`, never a silent double-reservation
- `reserved_fields_consistent` CHECK constraint (Epic 2) is never violated by this code path
- Reserving your own listing returns `400`, not `409`
- **Concurrency test written explicitly**: spawn two simultaneous requests against the same listing_id and assert exactly one succeeds
  **Technical Implementation Notes:**
- This is the centerpiece engineering ticket of the whole project per the epics doc — budget real time for the concurrency test, not just the happy-path handler.
- Lock scope is per-row (`WHERE id = $1`), so this must not become a table-wide lock — confirm via `EXPLAIN` or a quick multi-listing concurrent test that unrelated listings don't block each other.
- Lives at `features/listings/state_machine.rs`.

---

### CM-4.7 — State machine: `mark-sold` and `unreserve`

**Description:** Implement the remaining two state transitions using the identical `FOR UPDATE` locking pattern established in CM-4.6.
**Acceptance Criteria:**

- `POST /listings/{id}/mark-sold`: only valid from `reserved`, only callable by `seller_id`; transitions to `sold`
- `POST /listings/{id}/unreserve`: valid from `reserved`, callable by either the seller or the reserving buyer; returns to `active` and clears `reserved_by`/`reserved_at`
- Both use the same lock-then-check-then-transition pattern as `reserve` — an "impossible" transition (e.g. `active → sold` directly) is rejected by the guard inside the lock, not just by handler-level convention
- Concurrent `mark-sold` and `unreserve` calls on the same reserved listing resolve deterministically (one wins, the other gets a `409`)
  **Technical Implementation Notes:**
- Reuse/extend `state_machine.rs` from CM-4.6 — these three functions should share the row-locking scaffolding rather than duplicating the `FOR UPDATE` query independently.

---

### CM-4.8 — Stale-reservation cleanup background task

**Description:** Implement the periodic job that auto-unreserves listings stuck in `reserved` for over 48 hours.
**Acceptance Criteria:**

- Background task runs every few minutes, finds listings where `status = 'reserved' AND reserved_at < now() - interval '48 hours'`
- Auto-unreserve uses the **same** `FOR UPDATE` pattern as CM-4.7's manual `unreserve`, so it cannot race against a concurrent seller-initiated `mark-sold` call
- Task logs each auto-unreserve action (for later debugging/support purposes)
- Task failure on one listing doesn't halt processing of the rest of the batch
  **Technical Implementation Notes:**
- `actix_rt::spawn` + `tokio::time::interval`, per TRD §4.4 — same pattern as CM-3.10; consider whether a shared periodic-runner helper is worth factoring out at this point since this is the second identical pattern.

---

## Epic 5: Full-Text Search

### CM-5.1 — `GET /listings?q=...` ranked search

**Description:** Extend the browse endpoint (CM-4.2) with full-text search using the `search_vector` column and trigger already in place from Epic 2.
**Acceptance Criteria:**

- `q` query param triggers `plainto_tsquery('english', $1)` matched against `search_vector`, combined with the existing `status = 'active'` filter
- Results ordered by `ts_rank(search_vector, plainto_tsquery(...)) DESC`
- Empty/whitespace-only `q` falls back to the non-search browse behavior from CM-4.2 rather than erroring
- Works correctly in combination with existing filters (`category`, `min_price`, `max_price`) and pagination
  **Technical Implementation Notes:**
- Exact query pattern per TRD §3: `WHERE status = 'active' AND search_vector @@ plainto_tsquery('english', $1) ORDER BY ts_rank(...) DESC LIMIT $2`.
- Cursor pagination (CM-4.2) combined with rank-ordering needs care — a naive `(created_at, id)` cursor won't work once ordering is by rank instead of recency; decide and document the pagination strategy for ranked results (e.g. cursor encodes rank + id, or simplify to page-limited results without deep pagination for MVP search).

---

### CM-5.2 — Search relevance verification (title-weighted-over-description)

**Description:** Write a focused test/verification pass confirming the trigger's weighting behaves as intended in real query results, not just at the trigger level.
**Acceptance Criteria:**

- Test seeds listings where a term appears only in the title vs. only in the description, and confirms the title-match ranks higher via `ts_rank`
- Test confirms updating a listing's title/description re-ranks it correctly on the next search (trigger re-fires on update, not just insert)
  **Technical Implementation Notes:**
- This ticket is deliberately separated from CM-2.2's schema work and CM-5.1's endpoint work — it's the "does the ranking actually feel right in practice" checkpoint, worth its own small ticket since it's easy to ship a technically-working trigger that ranks unintuitively.

---

## Epic 6: Image Upload Pipeline

### CM-6.1 — R2 client setup & `POST /images/presign`

**Description:** Wire up the Cloudflare R2 client and implement the presigned-URL issuance endpoint so the backend never proxies image bytes.
**Acceptance Criteria:**

- R2 client configured in `AppState` (bucket, credentials from `Config`)
- `POST /images/presign` accepts `{ content_type, listing_id }`, validates `content_type` against an allowlist (`image/jpeg`, `image/png`, `image/webp`), returns a time-limited presigned PUT URL
- Enforces max 3 images per listing **before** issuing a presign (reject the 4th with a clear error) — count check against the `images` table for that `listing_id`
- Only the listing's owner can request a presign for it
  **Technical Implementation Notes:**
- Use an S3-compatible Rust client crate (R2 is S3-compatible) — confirm which crate the team standardizes on (`aws-sdk-s3` pointed at R2's endpoint is a common approach) and document the choice in the PR.
- Presign expiry should be short (minutes), just long enough for the client to complete the upload.

---

### CM-6.2 — `POST /images/confirm`

**Description:** Register a successfully-uploaded image against a listing after verifying it actually landed in R2.
**Acceptance Criteria:**

- Accepts `{ listing_id, object_key }`, performs a HEAD request against R2 to confirm the object exists and is within size limits before inserting
- Inserts into `images` table with the correct `position` (0, 1, or 2), respecting the `max_three_images` unique constraint from Epic 2
- HEAD check failure (object missing/oversized) returns a clear error, does not insert a phantom row
- Confirms ownership: `object_key`'s associated `listing_id` must belong to the authenticated user
  **Technical Implementation Notes:**
- The HEAD check is the key integrity guard here — a presign alone doesn't guarantee the client actually uploaded successfully or uploaded something matching the allowlist, so don't skip this step even though it's tempting to trust the presign step alone.

---

### CM-6.3 — `DELETE /images/{id}`

**Description:** Implement owner-only image removal.
**Acceptance Criteria:**

- Only the listing owner can delete an associated image
- Deletes both the `images` row and the underlying R2 object (or documents/queues async cleanup if synchronous R2 delete isn't desired in the request path)
- Deleting an image correctly shifts/doesn't break `position` ordering for remaining images (decide: re-pack positions, or allow gaps — document the choice, since the `max_three_images` unique constraint is on `(listing_id, position)` not on count)
  **Technical Implementation Notes:**
- If choosing not to re-pack positions, confirm the presign/confirm flow (CM-6.1/6.2) correctly finds the next free position slot rather than assuming 0/1/2 are always contiguous.

---

## Epic 7: WebSocket Chat Infrastructure

### CM-7.1 — `ChatServer` actor & registry

**Description:** Implement the single-instance `ChatServer` actor that owns the in-memory user-session registry.
**Acceptance Criteria:**

- `ChatServer` holds `HashMap<Uuid, Vec<Addr<ChatSession>>>` supporting multiple concurrent devices/sessions per user
- Exposes internal messages for: register session, deregister session, check-if-online, forward-message-to-user (used later by Epic 8's persistence logic)
- `ChatServer`'s address is added to `AppState` (replacing the placeholder from CM-1.5)
- Unit tests cover: registering two sessions for the same user, deregistering one leaves the other active, deregistering the last one clears the user's entry entirely
  **Technical Implementation Notes:**
- Built on `actix` (the actor framework) via `actix-web-actors` for the WS integration layer.
- Keep `ChatServer`'s public message API minimal and well-typed — Epic 8 will depend on it heavily for message forwarding.
- Lives at `apps/api/src/features/chats/ws.rs`.

---

### CM-7.2 — WS handshake auth & `ChatSession` connect lifecycle

**Description:** Implement the `GET /ws/chats?token=...` upgrade endpoint with pre-upgrade JWT validation and `ChatSession` actor spawning/registration.
**Acceptance Criteria:**

- JWT (passed as query param, per TRD §2.3 rationale re: cross-platform header limitations) is validated via CM-3.2's `verify_access_token` **before** the WS upgrade completes
- Invalid/expired token → `401`, no socket opened
- Valid token → `ChatSession` actor spawned, registers itself with `ChatServer` (CM-7.1) under the authenticated `user_id`
- Integration test: connecting with a valid token succeeds and appears in the registry; connecting with an invalid token is rejected pre-upgrade
  **Technical Implementation Notes:**
- `actix-web-actors::ws` handshake helpers; validate the token synchronously in the handler before calling `ws::start`.

---

### CM-7.3 — Heartbeat (ping/pong) & dead-connection reaping

**Description:** Implement the 15s ping / 30s pong-timeout heartbeat so a dropped TCP connection doesn't stay marked "online" indefinitely.
**Acceptance Criteria:**

- `ChatSession` sends a ping every 15s via `ctx.run_interval`
- If no pong is received within 30s of the last ping, the session is dropped and deregistered from `ChatServer`
- Test simulates a non-responding client and confirms deregistration occurs within the expected window
  **Technical Implementation Notes:**
- Standard Actix WS heartbeat pattern — track `last_heartbeat: Instant` on the session actor, check it in the same `run_interval` closure that sends pings.

---

### CM-7.4 — Presence tracking & disconnect handling

**Description:** Implement online/offline presence notifications to open chat threads' counterparts, and clean deregistration on disconnect.
**Acceptance Criteria:**

- On session registration, if it's the user's first active session, mark them online and (optionally) notify counterparts in open threads
- On `Stopping` (graceful or heartbeat-timeout-triggered), `ChatSession` deregisters from `ChatServer`
- If the disconnecting session was the user's last active one, mark them offline and notify counterparts
- Explicitly scoped as "cheap to add, not a hard MVP requirement" per TRD §2.6 — acceptable to ship a minimal version (e.g. presence flag without a full pub/sub fan-out) if time is tight, but the connect/disconnect registry bookkeeping itself is required
  **Technical Implementation Notes:**
- This ticket can be trimmed in scope if Week 4 is running long — the epics doc explicitly flags presence as nice-to-have. The underlying register/deregister correctness (shared with CM-7.1/7.2) is not optional; the _notification_ half is what's trimmable.

---

## Epic 8: Chat Persistence & Message Delivery

### CM-8.1 — `POST /chats` idempotent thread creation

**Description:** Implement thread creation/lookup for a buyer starting a conversation about a listing.
**Acceptance Criteria:**

- Accepts `{ listing_id }`; derives `buyer_id` from the authenticated user and `seller_id` from the listing
- Idempotent: if a thread already exists between this buyer and this listing's seller for this listing, returns the existing thread rather than erroring or duplicating (backed by the `unique_thread` constraint from Epic 2)
- A seller cannot start a thread on their own listing (400)
  **Technical Implementation Notes:**
- Use `INSERT ... ON CONFLICT (listing_id, buyer_id) DO NOTHING RETURNING *`, falling back to a `SELECT` if the insert hit the conflict — a clean way to get idempotency out of the existing unique constraint without a separate check-then-insert race.

---

### CM-8.2 — `GET /chats` and `GET /chats/{id}/messages`

**Description:** Implement thread listing and cursor-paginated message history.
**Acceptance Criteria:**

- `GET /chats` returns the authenticated user's threads ordered by `last_message_at DESC`, including an unread count per thread
- `GET /chats/{id}/messages` is cursor-paginated, newest-first, supporting a `before` cursor for infinite scroll upward
- Only thread participants (buyer or seller) can access either endpoint for a given thread — others get `403`/`404`
- Unread count calculation is correct against `messages.read_at IS NULL` scoped to messages not sent by the requesting user
  **Technical Implementation Notes:**
- This endpoint is explicitly called out in TRD §2.6 as the "ground truth" fallback — REST history must reflect reality even if a WS message was dropped in-flight, so don't take shortcuts here assuming the WS layer (Epic 7) is the source of truth.

---

### CM-8.3 — Message send flow: persist-first, live-forward, or mark-undelivered

**Description:** Implement the core send pipeline triggered by a `{ "type": "send", ... }` WS message: persist to Postgres first, then attempt live delivery.
**Acceptance Criteria:**

- On receiving a send message, `ChatSession` forwards to `ChatServer`, which persists the message to Postgres **before** attempting any live delivery (a message not in the DB never "happened," even if delivery fails)
- `chats.last_message_at` is updated as part of the same logical operation
- If the recipient has an active session in the registry (CM-7.1), the message is forwarded directly over their socket(s) and `delivered_at` is set
- If the recipient has no active session, the message remains `delivered_at = NULL` and an FCM push is fired server-side (not client-triggered)
- Integration test: send while recipient online → live delivery confirmed; send while recipient offline → row persisted, `delivered_at` null, push fired
  **Technical Implementation Notes:**
- This is the epic's centerpiece, analogous to CM-4.6 in Epic 4 — get the ordering (persist → forward/push) right and test both branches explicitly, not just the happy path.
- FCM server-side call belongs in `features/chats/repo.rs` or a small dedicated notifier module — keep it decoupled from the actor message-handling code so it's independently testable.

---

### CM-8.4 — Offline delivery / reconnect sync

**Description:** Implement the reconnect-time catch-up flow so a client that was offline receives everything it missed.
**Acceptance Criteria:**

- On reconnect, client can send `{ "type": "sync", "since": "<chat_id, cursor>" }` and receive any missed messages
- Alternatively/additionally, server proactively pushes any messages with `delivered_at IS NULL` for that user's threads immediately on reconnect
- Confirms the `idx_messages_undelivered` partial index (Epic 2) is actually used by this query path (spot-check via `EXPLAIN`)
- Messages delivered via sync have `delivered_at` updated accordingly
  **Technical Implementation Notes:**
- This ticket depends on CM-7.2 (connect lifecycle) and CM-8.3 (the undelivered-message state it's syncing) both being complete.

---

### CM-8.5 — Per-user rate limiting on message sends

**Description:** Apply `actix-governor` rate limiting to the message-send path to blunt spam.
**Acceptance Criteria:**

- Message sends are rate-limited per `user_id` (e.g. 30 messages/min), not per-IP (a user might reconnect from different networks)
- Exceeding the limit returns a clear rejection over the WS connection (not just silently dropped) so the client can surface feedback
- Rate limit is enforced at the point messages enter `ChatServer`, not bypassable via reconnecting with a new socket
  **Technical Implementation Notes:**
- `actix-governor` is built primarily for HTTP middleware; since this limit applies inside a WS actor message handler rather than an HTTP request, confirm whether `actix-governor`'s rate limiter can be used directly as a standalone keyed limiter here, or whether a lighter hand-rolled per-user token-bucket (e.g. via a `HashMap<Uuid, ...>` in `ChatServer` state) is the more natural fit for this specific call site.

---

## Epic 9: Reports & Moderation

### CM-9.1 — `POST /reports` submission endpoint

**Description:** Let authenticated users flag a listing or another user.
**Acceptance Criteria:**

- Accepts `reason` plus either `listing_id` or `reported_user_id` (matching the `report_target` CHECK constraint from Epic 2 — at least one must be present)
- `reporter_id` derived from the authenticated user, never from the request body
- New report inserted with `status = 'open'`
- Basic validation: `reason` non-empty, reasonable max length
  **Technical Implementation Notes:**
- Straightforward CRUD-style handler in `features/reports/` — low complexity relative to other epics, matches the epics doc's note that this is safely deferrable if time is tight.

---

### CM-9.2 — Admin-only review endpoint with DB-rechecked role

**Description:** Implement the moderation-side endpoint for reviewing and updating report status, with the admin check re-read from the DB rather than trusted from a JWT claim.
**Acceptance Criteria:**

- `GET /reports` (list, filterable by `status`) and a status-update endpoint (e.g. `PATCH /reports/{id}`) both require `role = 'admin'`
- The role check queries the `users` table fresh on each request — **not** read from any JWT claim — so a demoted admin loses access immediately, even mid-way through their access token's 10–15 min TTL
- Non-admin users get `403`
- Status transitions limited to the documented values (`open` → `reviewed`/`dismissed`)
  **Technical Implementation Notes:**
- This is a deliberate deviation from "trust the JWT" elsewhere in the system — per TRD §2.5.1, this is the one place role data must be re-verified server-side because moderation actions are sensitive enough to warrant it. Make sure this is a small, explicit DB lookup, not accidentally reused JWT-claim logic copy-pasted from elsewhere.

---

## Epic 10: Flutter Client — Core Wiring

### CM-10.1 — `forui` integration & base theming

**Description:** Add the `forui` component library and establish the app's base theme, matching the decision in TRD §5.
**Acceptance Criteria:**

- `forui`, `forui_assets` added to `pubspec.yaml` per the versions noted in the TRD
- Base `FTheme`/app theme configured (color scheme, typography) as the single source of visual truth for the app
- A basic screen (e.g. splash or home shell) renders using `forui` components to confirm the integration works end-to-end
  **Technical Implementation Notes:**
- Consult `forui`'s CLI for theme/style boilerplate generation per the TRD's mention of a "bundled CLI for theme/style boilerplate" — use it rather than hand-rolling theme setup from scratch.
- Consider the `frontend-design` skill for broader visual design guidance on top of `forui`'s defaults.

---

### CM-10.2 — API client & Riverpod provider foundation

**Description:** Build the core HTTP client wrapper and the base Riverpod provider structure the rest of the app's features will build on.
**Acceptance Criteria:**

- `core/` API client wraps requests to the backend's `/api/v1` base path, attaching `Authorization: Bearer <token>` automatically when a token is present
- A `dio` or `http`-based client (pick one, document the choice) with centralized error mapping so feature code doesn't hand-roll HTTP error handling per call
- Riverpod `ProviderScope` wired at app root; a base `apiClientProvider` exposed for feature providers to depend on
- Environment-based base URL config (local dev backend vs. deployed Shuttle.rs URL)
  **Technical Implementation Notes:**
- This ticket establishes the pattern every subsequent feature provider follows — keep the client's public interface small and typed (e.g. typed request/response methods per endpoint group) rather than a raw generic "make a request" escape hatch used everywhere.

---

### CM-10.3 — Auth token storage & automatic refresh handling

**Description:** Implement secure client-side storage of access/refresh tokens and automatic refresh-on-401 handling.
**Acceptance Criteria:**

- Tokens stored via secure platform storage (not plain `SharedPreferences`) — e.g. `flutter_secure_storage`
- A request that fails with `401` due to an expired access token triggers an automatic `/auth/refresh` call, then retries the original request once
- If refresh itself fails (revoked family, expired refresh token), the app clears stored tokens and routes the user to the login screen
- Concurrent requests that all hit `401` simultaneously don't each independently trigger a refresh call (single in-flight refresh, others await it)
  **Technical Implementation Notes:**
- The "don't refresh N times concurrently" requirement is the trickiest part here — a simple approach is a Riverpod-held `Future<String>? _inFlightRefresh` that concurrent callers await instead of re-triggering.
- This client-side logic is the mirror image of CM-3.7/3.8's server-side rotation — make sure the retry logic correctly swaps in the _new_ access token before retrying, not the stale one.

---

### CM-10.4 — `apps/mobile/lib/features/auth/` — signup, login, verify-email screens

**Description:** Build the auth UI flows wired to the `/auth` endpoints.
**Acceptance Criteria:**

- Signup screen: email/password/display-name form with client-side validation mirroring server rules (email format, password length, name length) for fast feedback, but server response is still the authority
- Login screen: handles the "email not verified yet" error distinctly from "wrong credentials" (per CM-3.6's distinguishable error)
- Verify-email deep link (or manual entry, depending on how the link is delivered to a mobile client) completes verification and routes to login
- Riverpod `AuthController`/provider manages auth state (logged out / logging in / logged in) consumed by the rest of the app for route guarding
  **Technical Implementation Notes:**
- `apps/mobile/lib/features/auth/` mirrors `apps/api/src/features/auth/` per TRD §1.4's naming convention.
- Use `forui` form components (CM-10.1) for consistency rather than raw Material widgets.

---

### CM-10.5 — `apps/mobile/lib/features/listings/` — browse, filter, search, detail

**Description:** Build the listing browse/search/detail screens wired to the `/listings` endpoints.
**Acceptance Criteria:**

- Browse screen: category filter, search bar (`q` param), infinite-scroll pagination consuming the cursor-based API
- Detail screen: shows images, price/barter status, seller name, and reserve/mark-sold/unreserve actions appropriate to the viewer's role (buyer vs. seller) and the listing's current status
- Loading, empty, and error states present for both browse and detail (full polish is Epic 12, but basic states should exist here, not be entirely deferred)
- Riverpod providers for listing list (paginated) and listing detail, following the pattern from CM-10.2
  **Technical Implementation Notes:**
- Reserve/mark-sold/unreserve actions should optimistically reflect the expected new status but reconcile with the server response, since a `409 Conflict` (lost the race) is an expected, handleable outcome per the backend's design — not an unexpected error.

---

### CM-10.6 — `apps/mobile/lib/features/listings/` — create/edit with image upload

**Description:** Build the listing creation and editing UI, including the presign → upload → confirm image flow.
**Acceptance Criteria:**

- Create/edit form covers all `POST`/`PATCH /listings` fields
- Image picker allows up to 3 images; for each, the client requests a presign (`POST /images/presign`), uploads directly to R2 with the returned URL, then calls `POST /images/confirm`
- Upload progress/failure per-image is surfaced to the user (a failed upload doesn't silently drop that image)
- Edit form respects the backend's active-only restriction — UI disables/hides edit actions when a listing isn't `active`, though the server remains the source of truth
  **Technical Implementation Notes:**
- The client never proxies image bytes through the backend — confirm the upload `PUT` goes directly to the presigned R2 URL from the Flutter HTTP client, not through `core`'s API client wrapper (which is for backend calls only).

---

### CM-10.7 — `apps/mobile/lib/features/categories/`

**Description:** Build the (likely simple, mostly-static) category selection UI feeding into listing create/edit and browse filters.
**Acceptance Criteria:**

- Categories fetched from the backend (if a `GET /categories`-style endpoint exists — confirm whether Epic 4/TRD scoped one; if categories are seed data only with no dedicated list endpoint, document that and source them via the listings query params instead) and cached client-side
- Category picker used consistently in both the browse filter (CM-10.5) and create/edit form (CM-10.6)
  **Technical Implementation Notes:**
- Flag during planning: the TRD's REST table doesn't explicitly list a `GET /categories` endpoint. If genuinely missing from the backend scope, this ticket may need a small backend addendum ticket, or categories can be a small hardcoded/config list for MVP — resolve this ambiguity before starting, don't guess silently.

---

## Epic 11: Flutter Client — Real-Time Chat

### CM-11.1 — WebSocket client connection & Riverpod chat provider

**Description:** Build the client-side WS connection lifecycle wired into a Riverpod provider, mirroring the backend's connect/heartbeat/reconnect design.
**Acceptance Criteria:**

- WS client connects to `/ws/chats?token=<access_token>`, using the currently valid access token from CM-10.3's token storage
- Handles the server's heartbeat (responds to pings) so the connection isn't reaped by the 30s timeout
- On unexpected disconnect, client attempts reconnect with backoff, re-authenticating with a (possibly refreshed) token
- Riverpod provider exposes connection state (connected/connecting/disconnected) to the rest of the chat UI
  **Technical Implementation Notes:**
- `web_socket_channel` package, per the TRD's own reference to it as the reason query-param auth was chosen over headers.
- If the access token expires while a long-lived WS connection is open, decide and implement the reconnect-with-fresh-token behavior — don't assume the socket outlives a 10–15 min access token without a plan.

---

### CM-11.2 — Thread list & message history (REST-backed)

**Description:** Build the chat thread list and message history screens backed by `GET /chats` and `GET /chats/{id}/messages`.
**Acceptance Criteria:**

- Thread list shows counterpart name, listing context, last message preview, unread count, ordered by `last_message_at`
- Message history screen paginates upward (`before` cursor) as the user scrolls back
- Initial load and pagination both go through REST, independent of WS connection state (per TRD §2.6 — REST is ground truth even if WS is momentarily down)
  **Technical Implementation Notes:**
- Riverpod provider for thread list should be simple to keep in sync with CM-11.3's live-update logic — consider whether the same provider that holds REST-loaded threads is the one live WS events mutate, to avoid two divergent sources of truth in the UI layer.

---

### CM-11.3 — Live message handling & reconnect/sync integration

**Description:** Wire incoming live WS messages into the chat UI, and implement the client side of the reconnect/sync protocol from CM-8.4.
**Acceptance Criteria:**

- Messages received live over the WS update the relevant open thread's message list in real time without a manual refresh
- On reconnect, client sends the `{ "type": "sync", "since": ... }` message (or receives the server's proactive undelivered push) and merges any missed messages into local state without duplicating already-seen messages
- Sending a message optimistically appears in the sender's UI immediately, then reconciles with the server-confirmed state (handles the case where a send fails or is rate-limited per CM-8.5)
  **Technical Implementation Notes:**
- Message de-duplication on sync matters here — messages have stable server-assigned `id`s, so merge logic should key off that rather than assuming ordering alone is sufficient.

---

### CM-11.4 — FCM push notification handling (client-side)

**Description:** Register the client for FCM push and handle incoming notifications for new messages when the app is backgrounded/closed.
**Acceptance Criteria:**

- App registers its FCM token with the backend (confirm/implement the registration endpoint if not already covered elsewhere — likely a small addition to the `auth` or `chats` feature; flag if missing from backend scope)
- Tapping a push notification deep-links into the relevant chat thread
- Foreground message handling doesn't double-notify when the WS connection is already live and has delivered the message via CM-11.3
  **Technical Implementation Notes:**
- Same ambiguity flag as CM-10.7: the TRD mentions FCM push is "fired server-side" (CM-8.3) but doesn't explicitly detail a token-registration endpoint in its REST table — confirm with backend scope before starting; likely needs a small `POST /auth/fcm-token` or similar addendum if it doesn't already exist.

---

## Epic 12: Hardening, Rate Limiting & Error States

### CM-12.1 — Rate limiting audit across all sensitive endpoints

**Description:** Confirm `actix-governor` limits are actually applied and correctly configured across every endpoint identified as sensitive in the TRD, not just the ones built first.
**Acceptance Criteria:**

- Checklist covering: `/auth/login`, `/auth/signup` (per-IP + per-email, CM-3.6), message sends (per-user, CM-8.5), and a decision recorded for any other mutating endpoint considered but deliberately left unlimited (e.g. `/listings` create — document the reasoning either way)
- Each limited endpoint has an integration test confirming the limit actually triggers a rejection at the expected threshold
- Rate limit rejection responses have a consistent, documented shape (ideally via `AppError`, e.g. a `429` variant if not already present — add one if CM-1.3 didn't include it)
  **Technical Implementation Notes:**
- This ticket is explicitly an audit/closure pass, not new endpoint-by-endpoint feature work — its job is to catch anything Epic 3/8 shipped without full test coverage under time pressure.

---

### CM-12.2 — Client-side empty/error/loading states across all screens

**Description:** Do a systematic pass across every Flutter screen ensuring the three baseline UI states are handled, not just the happy path.
**Acceptance Criteria:**

- Every screen that fetches data (browse, detail, thread list, message history, profile) has a distinct loading state, empty state (zero results, not an error), and error state (with a retry action where applicable)
- Network failures (no connectivity) are distinguished from server errors (5xx) where feasible, with appropriately different messaging
- Form submission errors (422 field-level validation from the backend) are mapped to inline field errors, not just a generic toast
  **Technical Implementation Notes:**
- This is a breadth ticket, not a depth ticket — consider splitting by feature area (auth/listings/chat) into sub-tasks if it proves too large for one PR, but keep it as one ticket at the epic-list granularity per the instructions.

---

### CM-12.3 — Server-side validation edge-case sweep

**Description:** Systematically verify every mutating endpoint's `422` validation behavior against edge cases beyond the ones exercised by earlier feature tickets' happy-path tests.
**Acceptance Criteria:**

- Checklist covering all mutating endpoints from the TRD's REST tables (§2.2–2.5), each tested against: missing required field, wrong type, boundary values (min/max length, negative price, etc.)
- Confirm validation failures never reach the DB layer (i.e., `validator` genuinely runs before any `sqlx` call, not just in most cases)
- Any endpoint found missing proper validation during this sweep gets a fix within this ticket's scope (small fixes) or spun out as a follow-up ticket (larger fixes)
  **Technical Implementation Notes:**
- Good candidate for a table-driven integration test file that iterates a list of `(endpoint, invalid_payload, expected_error)` cases rather than one-off tests per endpoint.

---

### CM-12.4 — HSTS & HTTPS enforcement confirmation in deployed environment

**Description:** Verify transport security is correctly enforced in the actual deployed environment, not just configured in code.
**Acceptance Criteria:**

- Confirm Shuttle.rs (or Fly.io fallback) terminates TLS correctly for the deployed URL
- `Strict-Transport-Security` header is present on responses from the deployed instance (not just asserted in a unit test against local middleware config)
- A plain HTTP request to the deployed URL is redirected to HTTPS or rejected, not silently served
  **Technical Implementation Notes:**
- This is a deployed-environment verification ticket, not a code-writing ticket — the middleware itself may already exist from earlier work; this closes the loop by checking it against the real deploy target.

---

## Epic 13: Load Testing & Deployment Finalization

### CM-13.1 — `k6` load test targeting `POST /listings/{id}/reserve`

**Description:** Write and run a `k6` load test specifically hammering the highest-contention endpoint to produce real concurrency numbers.
**Acceptance Criteria:**

- `k6` script simulates many concurrent reserve attempts against the same listing_id, confirming exactly one succeeds per listing under load (extending CM-4.6's smaller in-process concurrency test to a real network-level load scenario)
- Script also covers a broader browse/search read-load scenario for baseline numbers
- Results (latency percentiles, success/conflict counts) are captured and documented in the repo (e.g. `apps/api/load-tests/results.md`) as the citable evidence for the "handled the race condition" story
  **Technical Implementation Notes:**
- Run against the deployed Shuttle.rs instance (or a staging deploy) rather than localhost, so numbers reflect real network/DB latency, not just in-process behavior.
- `k6` is free/open-source per the TRD — no new infra cost here, just tooling to install locally/in CI.

---

### CM-13.2 — CI: path-filtered `backend`/`frontend` jobs, fully wired

**Description:** Complete the CI workflow stubbed in CM-1.1, implementing the real steps for both jobs with correct path filtering.
**Acceptance Criteria:**

- `backend` job triggers on `paths: ['apps/api/**']`, runs `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` against an ephemeral Postgres service container (`sqlx::test`)
- `frontend` job triggers on `paths: ['apps/mobile/**']`, runs `flutter analyze`, `flutter test`
- Both jobs run in parallel when a PR touches both paths; a PR touching only one path skips the other job entirely
- CI passes on a clean `main` branch run
  **Technical Implementation Notes:**
- Use GitHub Actions' `paths:` filter at the job or workflow-trigger level; verify the skip behavior actually works with a test PR touching only one directory before considering this done.
- Postgres service container config should mirror the version/extensions used in Epic 2's migrations (`pgcrypto`, `citext`).

---

### CM-13.3 — CD: explicit `sqlx migrate run` deploy step + Shuttle.rs deploy

**Description:** Finalize the production deployment pipeline with migrations run as a separate, explicit step — never silently on app boot.
**Acceptance Criteria:**

- On merge to `main`: build → run `sqlx migrate run` against the target prod DB as its own CI/CD job step (visible in the pipeline, not hidden inside app startup) → deploy to Shuttle.rs
- Confirms CM-1.4's non-prod-auto-migrate / prod-explicit-migrate split is actually respected by this pipeline (i.e., the deployed binary itself does not also try to auto-migrate on boot in prod, which would be redundant/risky)
- Fly.io fallback deploy path is documented (config present or at least a runbook) in case Shuttle's free tier becomes limiting
  **Technical Implementation Notes:**
- This ticket depends on CM-1.7 (initial manual deploy) and CM-2.1–2.3 (migrations existing) — it's the automation of what was previously a manual process.

---

### CM-13.4 — Secrets audit

**Description:** Do a final pass confirming no secret material is committed to the repo and everything sensitive is properly injected via GitHub Actions secrets / Shuttle.rs config.
**Acceptance Criteria:**

- Checklist confirms: JWT signing keys, Resend API key, R2 credentials, DB URL are all sourced from secrets/env at deploy time, never present in any committed file (including `.env` — only `.env.example` should be committed)
- `git log` / `git grep` sweep for accidentally-committed secret-shaped strings across the full history, not just the current tree
- Any finding from the sweep is rotated (new key/credential issued) if a real secret was ever committed, not just removed from the current tree
  **Technical Implementation Notes:**
- If history-scrubbing turns out to be needed (a secret was committed and later removed but still in history), that's a bigger follow-up than this ticket's scope — flag it clearly rather than attempting a `git filter-repo` rewrite as a rushed sub-task of this ticket.

---

## Summary Table

| Epic                                 | Ticket Count | Notes                                          |
| ------------------------------------ | ------------ | ---------------------------------------------- |
| 1 — Backend Foundation               | 7            | No feature deps; first work started            |
| 2 — DB Schema & Migrations           | 4            | Blocks nearly everything backend-side          |
| 3 — Auth & Authorization             | 10           | Critical-path bottleneck per epics doc         |
| 4 — Listings CRUD & State Machine    | 8            | CM-4.6 is the project's centerpiece ticket     |
| 5 — Full-Text Search                 | 2            | Small, layered on Epic 4                       |
| 6 — Image Upload Pipeline            | 3            |                                                |
| 7 — WebSocket Chat Infrastructure    | 4            | CM-7.4 partially trimmable under time pressure |
| 8 — Chat Persistence & Delivery      | 5            | CM-8.3 is this epic's centerpiece              |
| 9 — Reports & Moderation             | 2            | Safe to defer to Phase 5 per epics doc         |
| 10 — Flutter Core Wiring             | 7            | CM-10.7 flags a possible backend scope gap     |
| 11 — Flutter Real-Time Chat          | 4            | CM-11.4 flags a possible backend scope gap     |
| 12 — Hardening & Error States        | 4            | Audit/closure tickets, not new features        |
| 13 — Load Test & Deploy Finalization | 4            |                                                |
| **Total**                            | **64**       |                                                |

**Flagged scope gaps to resolve before sprint planning:** CM-10.7 (categories list endpoint) and CM-11.4 (FCM token registration endpoint) both reference backend surface area not explicitly itemized in the TRD's REST tables — confirm during backlog grooming whether these need small backend addendum tickets under Epic 4 (categories) and Epic 3 or 8 (FCM token registration) respectively.
