# Campus Marketplace — Technical Requirements Document (TRD)

### Option B: Custom Rust + Actix-Web Backend

**Author:** Solo Developer
**Status:** Draft v1.0
**Scope:** MVP backend + Flutter client, as scoped in `campus-marketplace-build-plans.md`, Option B.

---

## 1. Architecture

### 1.1 Guiding principle

This is a one-person team. The architecture optimizes for **velocity and a legible mental model**, not for theoretical scale. Strict DDD (aggregates, repositories-as-interfaces, domain events, application/infrastructure/domain layering) is explicitly rejected for the MVP — it adds indirection a solo dev pays for on every change, with no team-coordination benefit to offset it. Instead:

> **Feature-first, modular monolith.** One Actix-Web binary. Code is organized by feature (vertical slice), not by technical layer. Each feature module owns its handlers, its DB queries, and its request/response types. Shared concerns (auth, DB pool, error types, config) live in a thin `core` module every feature depends on.

This keeps the codebase scalable in the _real_ sense that matters here: you can add a feature without touching five layers, and you can still extract a feature into its own service later if the product genuinely outgrows a monolith (unlikely at campus-marketplace scale, but the module boundaries make it possible).

### 1.2 Project layout — monorepo

Everything lives in one repo, one root, one `git log`. The Rust backend and the Flutter client are sibling folders (each with their own native tooling — Cargo for one, the Flutter/Dart toolchain for the other), with a top-level `shared/` for the handful of artifacts genuinely shared between them, and a single root-level CI workflow that runs both toolchains' checks in parallel jobs.

```
campus-marketplace/                     # <- repo root
├── .github/
│   └── workflows/
│       └── ci.yml                      # single workflow, separate jobs: backend + frontend
├── backend/
│   ├── Cargo.toml
│   ├── migrations/                     # sqlx migrations (numbered, forward-only)
│   │   ├── 0001_init.sql
│   │   ├── 0002_listings.sql
│   │   └── ...
│   ├── src/
│   │   ├── main.rs                     # bootstraps config, DB pool, HttpServer
│   │   ├── core/
│   │   │   ├── config.rs                # env-based config struct (dotenvy + envy or manual)
│   │   │   ├── db.rs                    # PgPool setup, migration runner
│   │   │   ├── error.rs                 # AppError enum -> ResponseError impl
│   │   │   ├── auth/
│   │   │   │   ├── jwt.rs                # sign/verify access + refresh tokens
│   │   │   │   ├── middleware.rs         # Actix middleware/extractor for AuthUser
│   │   │   │   └── password.rs           # argon2 hash/verify wrappers
│   │   │   ├── state.rs                  # AppState { db, jwt_keys, r2_client, resend_client, ws_registry }
│   │   │   └── validation.rs             # shared validator helpers
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── mod.rs                 # route registration
│   │   │   │   ├── handlers.rs
│   │   │   │   ├── models.rs              # SignupRequest, LoginResponse, etc.
│   │   │   │   └── repo.rs                # sqlx queries for this feature
│   │   │   ├── listings/
│   │   │   │   ├── mod.rs
│   │   │   │   ├── handlers.rs
│   │   │   │   ├── models.rs
│   │   │   │   ├── repo.rs
│   │   │   │   └── state_machine.rs       # active/reserved/sold transition logic
│   │   │   ├── categories/
│   │   │   ├── images/                    # R2 upload/presign
│   │   │   ├── chats/
│   │   │   │   ├── mod.rs
│   │   │   │   ├── handlers.rs            # REST: history, list threads
│   │   │   │   ├── ws.rs                  # Actix actor: ChatSession + ChatServer
│   │   │   │   ├── models.rs
│   │   │   │   └── repo.rs
│   │   │   └── reports/
│   │   └── lib.rs                         # wires features into the App
│   └── tests/                             # integration tests per feature, using sqlx::test
├── frontend/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/                          # api client, riverpod providers, ws client, theming
│   │   ├── features/                      # mirrors backend/src/features/ 1:1: auth/ listings/ chats/ ...
│   │   └── shared_widgets/
│   └── test/
├── shared/
│   └── openapi.yaml                       # hand-written or generated API contract — see 1.3
└── README.md                              # single onboarding doc for the whole repo
```

**Why this split, not a Cargo/Flutter mixed workspace:** Cargo workspaces and Flutter/Dart's own workspace concept are separate tools that don't compose into one manifest — there's no single `Cargo.toml`-equivalent that governs both a Rust binary and a Flutter app. A monorepo here means _one repo, one CI pipeline, one set of PRs_, with `backend/` and `frontend/` each keeping their native, un-nested tool roots (`backend/Cargo.toml`, `frontend/pubspec.yaml`). This is the standard, low-friction way to monorepo a Rust+Flutter pair, and it's what the CI job matrix in §6 assumes.

**Rules of thumb for the solo dev:**

- A feature module never reaches into another feature's `repo.rs` directly. If `chats` needs to know a listing exists, it calls a small public function exposed from `listings::repo`, not a raw query against the `listings` table. This is the _only_ boundary discipline enforced — it's cheap and it's what actually prevents spaghetti as features multiply.
- `core::error::AppError` is the single error type returned by every handler, implementing Actix's `ResponseError` so every endpoint gets consistent JSON error bodies for free.
- No trait-based repository abstraction, no dependency-injection container. `sqlx::PgPool` is cloned into `AppState` and passed by reference. You are not going to swap Postgres for something else in an MVP; don't pay for the abstraction.

### 1.3 Cross-cutting concerns

| Concern    | Approach                                                                                                                                         |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Config     | `.env` locally, real env vars in Shuttle.rs/Fly.io. `dotenvy` + a `Config::from_env()` that fails fast on boot if anything required is missing.  |
| Errors     | `thiserror`-derived `AppError` → maps to `{ "error": { "code": "...", "message": "..." } }` JSON, correct HTTP status per variant.               |
| Validation | `validator` crate on request DTOs, checked at the top of each handler before touching the DB.                                                    |
| Logging    | `tracing` + `tracing-actix-web` middleware, structured JSON logs in prod.                                                                        |
| Migrations | `sqlx migrate run` on boot in non-prod, run explicitly as a CI/CD step in prod (never auto-migrate against prod on every deploy without review). |

### 1.4 Keeping backend and frontend in sync inside the monorepo

- `frontend/lib/features/` mirrors `backend/src/features/` by name (`auth`, `listings`, `images`, `chats`, `categories`, `reports`). When you add a feature on one side, the sibling folder on the other side is the obvious next stop — no separate repo to context-switch into.
- `shared/openapi.yaml` is the single contract both sides read. It doesn't have to be hand-maintained forever — `utoipa` (a Rust crate that derives OpenAPI specs from Actix handler annotations) can generate it from `backend/` directly into `shared/`, and the Flutter side can optionally codegen typed request/response models from it (e.g. via `openapi_generator` or just hand-written DTOs checked against it in review). For a solo dev at MVP scale, hand-written DTOs on both sides with the YAML as a manually-updated reference is a reasonable starting point; codegen is a nice upgrade once the API stabilizes, not a Week 1 requirement.
- Because both apps sit in one repo, a single PR can change a request shape in `backend/src/features/listings/models.rs` and the corresponding `frontend/lib/features/listings/` model in the same commit — the thing a split-repo setup would otherwise force into two PRs and a version-pinning dance.

---

## 2. REST API & WebSocket Design

### 2.1 Conventions

- Base path: `/api/v1`
- Auth: `Authorization: Bearer <access_token>` (JWT), except `/auth/*` public endpoints.
- All bodies: JSON. All list endpoints: cursor-based pagination (`?cursor=<opaque>&limit=20`), not offset — cheaper on Postgres and stable under concurrent writes.
- Every mutating endpoint validates its DTO with `validator` before any DB call; validation failures return `422` with field-level errors.

### 2.2 `/auth`

| Method | Path                 | Purpose                                     | Notes                                                                                                                                                                                                                                                                                                                                 |
| ------ | -------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| POST   | `/auth/signup`       | Create account with school email + password | Validates email domain against an allow-listed suffix (e.g. `@uniport.edu.ng`) server-side — never trust the client for this. Password hashed with `argon2` (Argon2id, tuned params). Row inserted with `email_verified = false`. Triggers `POST` to Resend with a signed verification link.                                          |
| POST   | `/auth/verify-email` | Consume the emailed token                   | Body: `{ "token": "<jwt>" }`. Token is a short-lived (30 min), single-purpose JWT (`purpose: "email_verify"`, `sub: user_id`), signed with the same key as auth tokens but a distinct `purpose` claim so it can't be replayed as an access token. Sets `email_verified = true`.                                                       |
| POST   | `/auth/login`        | Email + password → tokens                   | Rejects if `email_verified = false`. Returns `{ access_token, refresh_token, expires_in }`. Rate-limited per IP + per email (see §2.5).                                                                                                                                                                                               |
| POST   | `/auth/refresh`      | Rotate refresh token                        | Body: `{ refresh_token }`. Validates against `refresh_tokens` table (see §3), issues a new access+refresh pair, **revokes the old refresh token** (rotation, not reuse) — detects token replay if an already-used refresh token is presented again, and if so revokes the entire token family for that user as a compromise response. |
| POST   | `/auth/logout`       | Revoke a refresh token                      | Body: `{ refresh_token }`.                                                                                                                                                                                                                                                                                                            |
| GET    | `/auth/me`           | Current user profile                        | Requires access token.                                                                                                                                                                                                                                                                                                                |

**Request validation example — Signup:**

```rust
#[derive(Deserialize, Validate)]
struct SignupRequest {
    #[validate(email)]
    email: String,
    #[validate(length(min = 10))]
    password: String,
    #[validate(length(min = 1, max = 80))]
    display_name: String,
}
```

Domain allow-list check happens _after_ `.validate()` succeeds, in the handler, against a configured list (supports multiple campuses later without a code change).

### 2.3 `/listings`

| Method | Path                       | Purpose              | Notes                                                                                                                                                                                                            |
| ------ | -------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | `/listings`                | Browse/filter        | Query params: `category`, `q` (full-text search), `min_price`, `max_price`, `status` (defaults to `active` only), `cursor`, `limit`.                                                                             |
| GET    | `/listings/{id}`           | Detail view          | Includes seller display name, images, category.                                                                                                                                                                  |
| POST   | `/listings`                | Create               | Auth required + `email_verified`. Body: title, description, category_id, price (nullable = barter-only), condition. Image association happens via a separate upload step (§2.4), not multipart on this endpoint. |
| PATCH  | `/listings/{id}`           | Edit                 | Only the owner (`seller_id == auth user`), only while `status = 'active'`.                                                                                                                                       |
| DELETE | `/listings/{id}`           | Soft delete          | Sets `status = 'deleted'`, doesn't hard-delete (preserves chat/report history integrity).                                                                                                                        |
| POST   | `/listings/{id}/reserve`   | Claim for a buyer    | **This is the state-machine endpoint** — see §4 for the transactional logic. Body: `{ buyer_id }` (or derived from a chat context).                                                                              |
| POST   | `/listings/{id}/mark-sold` | Seller confirms sale | Only from `reserved`, only by `seller_id`.                                                                                                                                                                       |
| POST   | `/listings/{id}/unreserve` | Cancel a reservation | Returns to `active`. Seller or the reserving buyer can call this.                                                                                                                                                |

### 2.4 `/images`

| Method | Path              | Purpose                                      | Notes                                                                                                                                                                                                                                                                          |
| ------ | ----------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| POST   | `/images/presign` | Get a presigned R2 PUT URL                   | Body: `{ content_type, listing_id }`. Server never proxies image bytes — client uploads directly to R2 with the presigned URL, then calls the next endpoint. Enforces max 3 images/listing and a server-side content-type allowlist (`image/jpeg`, `image/png`, `image/webp`). |
| POST   | `/images/confirm` | Register an uploaded image against a listing | Body: `{ listing_id, object_key }`. Inserts into `images` table after a HEAD check against R2 confirms the object exists and is within size limits.                                                                                                                            |
| DELETE | `/images/{id}`    | Remove an image                              | Owner-only.                                                                                                                                                                                                                                                                    |

### 2.4a `/schools`

| Method | Path              | Purpose                        | Notes                                                                                                                                                                      |
| ------ | ----------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | `/schools`        | List all partner schools       | Public. Optional `?q=` search by name or domain (case-insensitive).                                                                                                         |
| GET    | `/schools/{id}`   | Get a single school            | Public.                                                                                                                                                                    |
| POST   | `/schools`        | Register a new partner school  | **Admin only.** Body: `{ name, domain }`. Domain must be unique — used for signup email matching. Returns `409` on duplicate domain.                                        |
| PATCH  | `/schools/{id}`   | Update a school                | **Admin only.** Partial update (only provided fields change). Returns `409` if new domain conflicts.                                                                       |
| DELETE | `/schools/{id}`   | Remove a partner school        | **Admin only.** Fails with `400` if users reference this school (FK violation). Admin role is re-checked from DB per §2.5.1 via the `AdminUser` extractor.                  |

### 2.5 `/chats`

| Method | Path                             | Purpose                                        | Notes                                                                                                                                                                                                       |
| ------ | -------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | `/chats`                         | List my chat threads                           | Ordered by `last_message_at desc`. Includes unread count per thread.                                                                                                                                        |
| GET    | `/chats/{id}/messages`           | Message history                                | Cursor-paginated, newest-first with `before` cursor for infinite scroll upward.                                                                                                                             |
| POST   | `/chats`                         | Start (or fetch existing) thread for a listing | Body: `{ listing_id }`. Idempotent — returns the existing thread if one already exists between this buyer and this listing's seller.                                                                        |
| WS     | `/ws/chats?token=<access_token>` | Live connection                                | See §2.6. Token passed as query param since browsers/Flutter's `web_socket_channel` can't set custom headers on the initial handshake uniformly across platforms; validated identically to the Bearer flow. |

### 2.5.1 Auth hardening — token design in depth

The refresh-token table and rotation-on-reuse behavior in §2.2/§3 are the backbone; this section makes the full threat model explicit.

**Access tokens (JWT, stateless, short-lived):**

- Lifetime: **10–15 minutes**. Short enough that a leaked access token (e.g. exfiltrated from device storage, logged accidentally, or intercepted) has a narrow window of use, without forcing re-login on every request.
- Signed with **RS256** (asymmetric), not HS256. The backend holds the private key; only the public key would ever need to be shared if any other service had to verify tokens independently. This also means a key-rotation event doesn't require redistributing a shared secret to every verifier.
- Claims kept minimal: `sub` (user_id), `exp`, `iat`, `purpose: "access"`, `email_verified`. No role/permission data that would go stale before the token expires — the `role` check for admin-only endpoints (§2.4a schools, §2.5.2 reports moderation) re-reads from the DB rather than trusting a JWT claim, so a demoted admin's already-issued tokens don't retain elevated access for their remaining 10-minute window in a way that matters (moderation actions are re-checked server-side regardless).
- Verified on every request via an Actix extractor (`core/auth/middleware.rs`) — signature, expiry, and `purpose` claim all checked; a `purpose: "email_verify"` token presented as an access token is rejected even though it's signed with the same key.

**Refresh tokens (opaque, DB-backed, rotating):**

- The token handed to the client is a high-entropy random value (256-bit, via `rand`'s CSPRNG), **not** a JWT. Only its hash (`argon2` or `sha256`, hash is sufficient here since the token itself is already high-entropy — no need for the slow KDF used on user passwords) is stored in `refresh_tokens.token_hash`. A DB leak (backup exposure, misconfigured replica, etc.) does not hand out usable refresh tokens.
- Lifetime: **14–30 days**, sliding — each successful `/auth/refresh` call extends the session by issuing a new refresh token with a fresh expiry, rather than the original expiry being a hard session cap. Inactive sessions still die on schedule.
- **Rotation on every use, single-use enforcement:** each refresh token is valid for exactly one `/auth/refresh` call. On use, it's marked `revoked = true` and a new refresh token is issued in the same DB transaction, sharing the same `family_id`.
- **Reuse detection = compromise signal:** if a refresh token with `revoked = true` is ever presented again, that's not a benign race — it means either a network retry duplicated a request (handled separately, see below) or a token was stolen and both the legitimate client and an attacker have used the same one. The server's response is to **revoke every token in that `family_id`**, forcing full re-authentication on all devices tied to that session lineage. This is the standard mitigation for refresh-token theft and is the reason rotation exists at all — a stolen-but-unused token is useless once the legitimate client's next refresh invalidates it; a stolen-and-used token trips the reuse alarm.
- **Legitimate retry vs. theft, in practice:** a brief grace window (a few seconds) where the _immediately preceding_ token in the same family is still accepted (rather than instantly nuking the family) absorbs mobile-network duplicate requests without weakening the security property — this grace window is tracked via a `superseded_by` pointer on the row rather than a bare boolean, so "reused within grace" and "reused after grace/after another rotation" are distinguishable.
- Refresh tokens are `DELETE`-eligible via a scheduled cleanup job for rows past `expires_at` — not required for correctness (expired tokens are already rejected), but keeps the table from growing unbounded.

**Password storage:**

- **Argon2id** (not Argon2i/d) via the `argon2` crate, with parameters tuned to the deploy target's actual CPU/memory budget (Shuttle.rs/Fly.io free tier is memory-constrained, so tuning is a deliberate step, not defaults left untouched) — target roughly 19 MiB memory / 2 iterations / 1 parallelism as a floor, adjusted upward if headroom allows, per current OWASP guidance.
- Timing-safe comparison is inherent to `argon2::PasswordHash::verify_password` — no hand-rolled `==` on hashes anywhere in the codebase.

**Transport & endpoint hardening:**

- HTTPS-only in every environment past local dev; Shuttle.rs/Fly.io terminate TLS at the edge, and the app additionally sets `Strict-Transport-Security` on responses.
- `/auth/login` and `/auth/signup` are rate-limited **per IP and per email** independently (via `actix-governor`), so an attacker can't route around an IP-based limit by rotating source addresses while hammering one target email, nor route around an email-based limit by spraying many emails from one IP.
- Login failure responses are identical (`401`, generic message) whether the email doesn't exist or the password is wrong — no user enumeration via differential error messages.
- `/auth/refresh` and `/auth/logout` invalidate tokens by DB write, so logout is immediate and server-enforced, not just "client throws away the token and hopes."

**Rate limiting (applies across `/auth` and message sends):** `actix-governor` middleware, keyed by IP for `/auth/login` and `/auth/signup` (e.g. 10 req/min), and by `user_id` for message sends (e.g. 30 messages/min) to blunt spam without needing a separate service.

### 2.6 WebSocket connection manager lifecycle

**Actors:** `ChatServer` (single instance, owns the registry) and one `ChatSession` actor per connected socket.

```
ChatServer {
    sessions: HashMap<Uuid /* user_id */, Vec<Addr<ChatSession>>>,  // multiple devices per user
}
```

**Lifecycle:**

1. **Connect.** Client opens `GET /ws/chats?token=...`. Actix-Web handshakes the WS upgrade; the JWT is validated _before_ the upgrade completes — an invalid/expired token gets a `401` and no socket is opened. On success, a `ChatSession` actor is spawned and registers itself with `ChatServer` under the user's `user_id`.
2. **Presence.** On registration, `ChatServer` marks the user online and optionally notifies open chat threads' counterparts (used for a lightweight "online" indicator; not a hard requirement for MVP but cheap to add here).
3. **Message send.** Client sends `{ "type": "send", "chat_id": "...", "body": "..." }` over the socket. `ChatSession` forwards to `ChatServer`, which:
   - Persists the message to Postgres first (source of truth — a message that isn't in the DB never "happened," even if delivery fails).
   - Updates `chats.last_message_at`.
   - If the recipient has an active session in the registry, forwards the message directly over their socket(s).
   - If the recipient has **no** active session, the message stays in Postgres in a delivered-but-unread state, and a push notification is fired via FCM (server-side call, not client-triggered — this is one of the few places Option B's own backend genuinely simplifies over Option A's client-triggered FCM hack).
4. **Offline delivery / reconnect.** On (re)connect, the client sends `{ "type": "sync", "since": "<chat_id, cursor>" }` or the server proactively pushes any messages with `delivered_at IS NULL` for that user's threads. This means the WebSocket is an optimization for _live_ delivery, not the source of truth for _eventual_ delivery — REST history (§2.3 `/chats/{id}/messages`) always reflects ground truth even if a socket message was dropped in-flight.
5. **Heartbeat.** `ChatSession` runs an Actix `ctx.run_interval` ping every 15s; if no pong within 30s, the session is dropped and deregistered from `ChatServer`. This bounds how long a dead TCP connection can be mistaken for "online."
6. **Disconnect.** On `Stopping`, `ChatSession` deregisters from `ChatServer`. If it was the user's last session, mark them offline.

This gives "reconnect-safe" behavior without a message queue: Postgres is the durable store, the WS registry is a purely in-memory, disposable routing table that gets rebuilt from scratch on every reconnect.

---

## 3. PostgreSQL Schema

```sql
-- 0001_init.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           CITEXT UNIQUE NOT NULL,          -- requires citext extension; case-insensitive email
    password_hash   TEXT NOT NULL,                    -- argon2id hash
    display_name    TEXT NOT NULL,
    email_verified  BOOLEAN NOT NULL DEFAULT FALSE,
    role            TEXT NOT NULL DEFAULT 'student',   -- 'student' | 'admin'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE EXTENSION IF NOT EXISTS "citext";

CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL,          -- sha256 hash of the opaque token, never the raw value
    family_id       UUID NOT NULL,          -- groups a rotation chain; revoking the family kills all descendants
    revoked         BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ,
    superseded_by   UUID REFERENCES refresh_tokens(id), -- points to the token this one rotated into
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens(family_id);
CREATE UNIQUE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

CREATE TABLE categories (
    id              SMALLSERIAL PRIMARY KEY,
    slug            TEXT UNIQUE NOT NULL,
    label           TEXT NOT NULL,
    sort_order      SMALLINT NOT NULL DEFAULT 0
);

CREATE TYPE listing_status AS ENUM ('active', 'reserved', 'sold', 'deleted');

CREATE TABLE listings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id     SMALLINT NOT NULL REFERENCES categories(id),
    title           TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    price_cents     INTEGER,                 -- NULL = barter-only
    condition       TEXT NOT NULL DEFAULT 'used', -- 'new' | 'used' | 'fair'
    status          listing_status NOT NULL DEFAULT 'active',
    reserved_by     UUID REFERENCES users(id),      -- set only while status = 'reserved'
    reserved_at     TIMESTAMPTZ,
    search_vector   TSVECTOR,                        -- generated column, see trigger below
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT reserved_fields_consistent CHECK (
        (status = 'reserved' AND reserved_by IS NOT NULL AND reserved_at IS NOT NULL)
        OR (status != 'reserved' AND reserved_by IS NULL)
    )
);

CREATE INDEX idx_listings_status_category ON listings(status, category_id);
CREATE INDEX idx_listings_seller ON listings(seller_id);
CREATE INDEX idx_listings_search ON listings USING GIN (search_vector);

-- Full-text search: keep search_vector in sync via trigger rather than a
-- generated column, since weighting title > description needs setweight().
CREATE FUNCTION listings_search_vector_update() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_listings_search_vector
    BEFORE INSERT OR UPDATE OF title, description ON listings
    FOR EACH ROW EXECUTE FUNCTION listings_search_vector_update();

CREATE TABLE images (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id      UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    object_key      TEXT NOT NULL,           -- R2 object key
    position        SMALLINT NOT NULL DEFAULT 0, -- display order, 0..2
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT max_three_images UNIQUE (listing_id, position)  -- combined with app-level count check
);
CREATE INDEX idx_images_listing ON images(listing_id);

CREATE TABLE chats (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id      UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    buyer_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seller_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT unique_thread UNIQUE (listing_id, buyer_id)  -- one thread per buyer per listing
);
CREATE INDEX idx_chats_buyer ON chats(buyer_id, last_message_at DESC);
CREATE INDEX idx_chats_seller ON chats(seller_id, last_message_at DESC);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id         UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body            TEXT NOT NULL,
    delivered_at    TIMESTAMPTZ,             -- set when pushed over an active socket
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_chat ON messages(chat_id, created_at);
CREATE INDEX idx_messages_undelivered ON messages(chat_id) WHERE delivered_at IS NULL;

CREATE TABLE reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id      UUID REFERENCES listings(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    reason          TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open', -- 'open' | 'reviewed' | 'dismissed'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT report_target CHECK (listing_id IS NOT NULL OR reported_user_id IS NOT NULL)
);
CREATE INDEX idx_reports_status ON reports(status);
```

**Foreign key summary:** `listings.seller_id → users`, `listings.category_id → categories`, `listings.reserved_by → users`, `images.listing_id → listings`, `chats.listing_id → listings`, `chats.{buyer_id,seller_id} → users`, `messages.chat_id → chats`, `messages.sender_id → users`, `reports.*_id → users/listings`. All `ON DELETE CASCADE` except `listings.reserved_by`, which is nulled out (not cascaded) so a deleted account doesn't corrupt an otherwise-valid listing state — this is handled by an app-level cleanup step, not a raw cascade, since "buyer deleted their account mid-reservation" is a business event worth its own handling (auto-unreserve), not a silent DB cascade.

**Full-text search query pattern** (used by `GET /listings?q=...`):

```sql
SELECT * FROM listings
WHERE status = 'active'
  AND search_vector @@ plainto_tsquery('english', $1)
ORDER BY ts_rank(search_vector, plainto_tsquery('english', $1)) DESC
LIMIT $2;
```

---

## 4. Listing State Machine — Transactional Enforcement

### 4.1 States and transitions

```
active ──reserve──▶ reserved ──mark-sold──▶ sold
   ▲                    │
   └────unreserve───────┘
```

`deleted` is reachable from `active` or `reserved` (a seller can pull a listing at any point before `sold`) but is modeled as a separate soft-delete flag transition, not shown above for clarity.

### 4.2 Why this needs a DB-level lock, not just application logic

The failure mode this guards against: two buyers tap "reserve" on the same listing within milliseconds of each other. If the check-then-write ("is it still active? if so, set reserved") happens as two separate statements without locking, both requests can read `status = 'active'` before either writes, and both succeed — a classic TOCTOU race. Application-level mutexes don't help because Actix-Web runs requests concurrently across worker threads/processes, and a future horizontally-scaled deployment (multiple backend instances behind a load balancer) makes in-process locking meaningless anyway. The lock has to live where the concurrent access is actually arbitrated: the database.

### 4.3 Implementation — `SELECT ... FOR UPDATE`

```rust
// features/listings/state_machine.rs

pub async fn reserve_listing(
    pool: &PgPool,
    listing_id: Uuid,
    buyer_id: Uuid,
) -> Result<Listing, AppError> {
    let mut tx = pool.begin().await?;

    // Row-level lock: any other transaction trying to SELECT ... FOR UPDATE
    // (or write to) this same row blocks here until this transaction commits
    // or rolls back. This serializes concurrent reserve attempts on the same
    // listing — the second request simply waits, then sees the post-commit state.
    let listing = sqlx::query_as!(
        Listing,
        r#"
        SELECT id, seller_id, status as "status: ListingStatus", reserved_by
        FROM listings
        WHERE id = $1
        FOR UPDATE
        "#,
        listing_id
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("listing"))?;

    if listing.status != ListingStatus::Active {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "listing is no longer available".into(),
        ));
    }

    if listing.seller_id == buyer_id {
        tx.rollback().await?;
        return Err(AppError::BadRequest("cannot reserve your own listing".into()));
    }

    let updated = sqlx::query_as!(
        Listing,
        r#"
        UPDATE listings
        SET status = 'reserved',
            reserved_by = $1,
            reserved_at = now(),
            updated_at = now()
        WHERE id = $2
        RETURNING id, seller_id, status as "status: ListingStatus", reserved_by
        "#,
        buyer_id,
        listing_id
    )
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(updated)
}
```

**Why this is correct under concurrency:**

- `FOR UPDATE` acquires an exclusive row lock the instant the row is read, inside the transaction. A second concurrent call to `reserve_listing` for the _same_ `listing_id` blocks at its own `SELECT ... FOR UPDATE` until the first transaction commits or rolls back — there is no window where both transactions observe `status = 'active'` simultaneously.
- Once the first transaction commits, the second transaction's blocked `SELECT` unblocks and returns the **post-commit** row — `status = 'reserved'` — so the status check correctly fails the second request with a `409 Conflict`, rather than double-reserving.
- The lock is scoped to a single row (`WHERE id = $1`), so reservations on _different_ listings never contend with each other — this doesn't become a global bottleneck as listing volume grows.
- `mark_sold` and `unreserve` follow the identical pattern: lock the row, assert the expected current state, transition, commit. Every transition function checks its own precondition inside the lock, so an "impossible" transition (e.g. marking `active → sold` directly, skipping `reserved`) is rejected by the same guard, not just by convention in the handler.

### 4.4 Timeout / stale-reservation handling

A reservation that's never confirmed or cancelled would otherwise lock a listing forever. MVP approach: a periodic background task (Actix `actix_rt::spawn` loop with `tokio::time::interval`, or a scheduled job if hosting supports it) runs every few minutes and auto-unreserves any listing where `status = 'reserved' AND reserved_at < now() - interval '48 hours'`, using the same `FOR UPDATE` pattern so it can't race against a concurrent `mark-sold` call from the seller.

---

## 5. Frontend: UI Component Library Selection

**Decision: `forui` (duobase.io) over `shadcn_ui`.**

| Criterion       | `forui`                                                                                                                                    | `shadcn_ui`                                                                                                                                                                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Release cadence | Frequent, active releases (multiple within the same month at time of writing) with clear changelogs                                        | Actively maintained, but the shadcn-for-Flutter space is split between this package and a separate, unrelated `shadcn_flutter` package from a different author — confusing for a solo dev searching docs/Stack Overflow/AI answers, since results and APIs mix across the two. |
| Documentation   | Dedicated docs site (forui.dev/docs) plus API reference, widget catalog, and a published roadmap                                           | Docs exist but are less centralized; the naming collision above compounds discoverability.                                                                                                                                                                                     |
| Breadth         | 40+ widgets, first-class `flutter_hooks` integration via a companion package, bundled CLI for theme/style boilerplate                      | Broad widget coverage as well, comparable maturity for core components.                                                                                                                                                                                                        |
| Testing signal  | Publisher explicitly calls out "well-tested" and ships nightly builds separately from stable, which signals a deliberate stability process | No equivalent explicit stability track called out.                                                                                                                                                                                                                             |

For a **solo developer**, the deciding factors are (1) not having to disambiguate two similarly-named packages while debugging, and (2) a single, current documentation source. `forui` wins on both. Riverpod integrates with either choice without friction — this decision only affects the widget/design-system layer.

```yaml
# pubspec.yaml (relevant excerpt)
dependencies:
  forui: ^0.22.0
  forui_assets: ^0.1.0
  flutter_riverpod: ^2.6.0
```

---

## 6. Deployment & CI/CD

- **CI (GitHub Actions), single `.github/workflows/ci.yml` at the repo root, two independent jobs:**
  - `backend` job — `working-directory: backend`, triggered via `paths: ['backend/**']` filtering so a frontend-only PR doesn't spin up a Postgres service container for nothing. Runs `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` (using `sqlx::test` against an ephemeral Postgres service container).
  - `frontend` job — `working-directory: frontend`, triggered via `paths: ['frontend/**']`. Runs `flutter analyze`, `flutter test`.
  - Both jobs run in parallel on every PR when both paths are touched; each is skippable independently when a change only touches one side — the main monorepo CI benefit over two separate repos' pipelines.
- **CD:** on merge to `main` — build the Rust binary from `backend/`, run `sqlx migrate run` against the target DB as an explicit, separate job (never bundled silently into app boot in prod), then deploy to **Shuttle.rs** (preferred: purpose-built for Rust, free hobby tier, minimal config) with **Fly.io** as the fallback if Shuttle's free tier constraints become limiting.
- **Secrets:** JWT signing keys, Resend/SendGrid API key, R2 credentials, DB URL — stored as GitHub Actions secrets and injected as env vars at deploy time, never committed.

---

## 7. Build Plan Alignment

This TRD implements the 6-week phased plan from `campus-marketplace-build-plans.md` Option B:

1. **Weeks 1–2:** `core` module, migrations 0001–0003 (users, categories, listings), JWT + Argon2 auth, Resend email flow, first Shuttle.rs deploy.
2. **Week 3:** `listings` + `images` features, R2 presigned upload flow, `tsvector` search.
3. **Week 4:** `chats` feature — REST endpoints, `ChatServer`/`ChatSession` actors, FCM push integration.
4. **Week 5:** Flutter client wiring (Riverpod providers for REST + a WS-backed chat provider), `forui` component adoption.
5. **Week 6:** `actix-governor` rate limiting, `reports` feature, `k6` load test against the reserve-listing endpoint specifically (the highest-contention path), final deploy.
