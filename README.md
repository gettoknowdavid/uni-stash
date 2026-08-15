# UniStash

A campus marketplace app for verified students to buy, sell, and barter items — think a trusted, school-only version of a classifieds app, with real-time chat and safe listing reservations.

Students sign up with a verified school email, list items for sale or trade, browse and search what's available, and message sellers directly. Listings move through a safe `active → reserved → sold` flow so two buyers can't accidentally claim the same item.

> **Status:** Active development (MVP). Not yet deployed.

---

## Stack

| Layer | Tech |
|---|---|
| Client | Flutter + Riverpod |
| UI components | `forui` |
| Backend | Rust + Actix-Web |
| Database | PostgreSQL (via `sqlx`) |
| Auth | Custom JWT (RS256 access tokens + rotating opaque refresh tokens) + Argon2id |
| Real-time chat | WebSockets (`actix-web-actors`) |
| Image storage | Cloudflare R2 (presigned uploads) |
| Email | Resend |
| Hosting | Shuttle.rs (Fly.io fallback) |

Full architecture, API design, schema, and rationale live in the project's TRD (Technical Requirements Document) — see `/docs` if present, or the project workspace.

---

## Repo layout

This is a monorepo: one repo, one CI pipeline, one set of PRs. The Rust backend and Flutter client are sibling folders, each with their own native, un-nested tooling root.

```
uni-stash/
├── .github/
│   └── workflows/
│       └── ci.yml          # single workflow, separate backend + frontend jobs
├── backend/
│   ├── Cargo.toml
│   ├── migrations/         # sqlx migrations, numbered, forward-only
│   └── src/
│       ├── core/           # config, db, error, auth, shared state
│       └── features/       # auth, listings, images, chats, categories, reports
├── frontend/
│   ├── pubspec.yaml
│   └── lib/
│       ├── core/           # API client, riverpod providers, theming
│       └── features/       # mirrors backend/src/features/ 1:1
├── shared/
│   └── openapi.yaml         # API contract referenced by both sides
├── .gitignore
├── LICENSE
└── README.md
```

**Why not a single Cargo/Flutter workspace?** Cargo workspaces and the Flutter/Dart toolchain don't compose into one manifest — there's no single file that governs both a Rust binary and a Flutter app. Keeping `backend/Cargo.toml` and `frontend/pubspec.yaml` independent, inside one repo, gets the collaboration benefits of a monorepo (one CI pipeline, one PR touching both sides when a request shape changes) without fighting the tooling.

**The one boundary rule:** a feature module never reaches into another feature's data layer directly. If `chats` needs to know a listing exists, it calls a small public function exposed from `listings`, not a raw query against the `listings` table.

---

## Getting started

### Prerequisites
- Rust (stable toolchain) + `sqlx-cli`
- Flutter SDK
- A local Postgres instance, or a free-tier hosted one (Neon / Supabase Postgres)

### Backend

```bash
cd backend
cp .env.example .env        # fill in DATABASE_URL, JWT keys, etc.
sqlx migrate run
cargo run
```

The server starts on the port configured in `.env`. `GET /health` should return `200 { "status": "ok" }`.

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

Point the app at your local backend by setting the base URL in the frontend's environment config (see `frontend/lib/core/`).

---

## CI

`.github/workflows/ci.yml` runs two path-filtered jobs so a frontend-only PR doesn't spin up a Postgres container for nothing, and vice versa:

- **backend** (`paths: backend/**`) — `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
- **frontend** (`paths: frontend/**`) — `flutter analyze`, `flutter test`

---

## License

All rights reserved — see [`LICENSE`](./LICENSE). This repo is public for portfolio and reference purposes; it is not open source, and reuse requires permission.
