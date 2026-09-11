# Uni-Stash API — Postman Collection

Postman collection (`$kind: http-request` YAML files), environment, and globals
for exercising the Uni-Stash backend locally or in deployed environments.

## Layout

```
apps/api/postman/
├── collections/Uni-Stash API/
│   ├── Admin Auth/         # /api/v1/admin/auth/*    — admin login, refresh, me, logout, password reset
│   ├── Admin Management/   # /api/v1/admin/admins    — create/list/update/deactivate admins
│   ├── Auth/               # /api/v1/auth/*          — signup, verify, login, refresh, password reset
│   ├── Categories/         # /api/v1/categories      — public list + admin CRUD
│   ├── Images/             # /api/v1/images/*        — presign, confirm, delete
│   ├── Listings/           # /api/v1/listings/*      — CRUD + reserve/unreserve/mark-sold
│   └── Schools/            # /api/v1/schools         — CRUD + search
├── environments/
│   └── dev.environment.yaml
└── globals/
    └── workspace.globals.yaml
```

## Getting started

1. Import the collection folder and `environments/dev.environment.yaml` into
   Postman (or use the Postman VS Code extension / `newman`).
2. Select the **Dev (Local)** environment. `baseUrl` defaults to
   `http://localhost:8080`.
3. Run **Auth → Login** (or **Admin Auth → Login** for admin routes). The
   response script stores `accessToken` / `refreshToken` (and
   `adminAccessToken` / `adminRefreshToken`) in collection variables, so
   protected requests authenticate automatically.
4. Some requests also save ids (e.g. `adminId`) for chained requests.

## Conventions

- Requests use `{{baseUrl}}` and bearer tokens via collection variables.
- Write requests show representative JSON bodies — adjust values to your
  seeded data before sending.
- The backend uses a uniform response envelope
  `{ "success": bool, "message": string, "data": ... | "error": ... }`.
- Rate limits apply per route group (e.g. listings and categories share the
  listings bucket); a 429 means you hit the bucket.

## Adding a new endpoint to the collection

1. Create `folders/<Feature>/<verb-noun>.request.yaml` matching the handler in
   `apps/api/src/features/<feature>/`.
2. Use `$kind: http-request`, set `order` (multiples of 1000 within the
   folder), and `auth: { type: noauth }` or bearer `{{accessToken}}` /
   `{{adminAccessToken}}` (admin-only routes).
3. Add `docs.description` with a request/response example and error table.

## Notes on Categories

Categories are **curated taxonomy managed by admins** via the API:

| Method | Path | Access |
| ------ | ---- | ------ |
| GET    | `/api/v1/categories`     | Public (no auth) — browse filter chips, pickers |
| POST   | `/api/v1/categories`     | Admin only (`categories: write`) |
| PATCH  | `/api/v1/categories/{id}` | Admin only (`categories: write`) |
| DELETE | `/api/v1/categories/{id}` | Admin only (`categories: write`) |

- Regular users (mobile app) only ever **read** the list; there is no
  user-facing category creation.
- `slug` is unique and must be lowercase letters/digits/hyphens; `sort_order`
  controls display order.
- **Deleting a category that still has listings returns `409 Conflict`** —
  reassign or delete the listings first. This guards against the schema's
  `ON DELETE CASCADE` destroying user data.
- For bootstrap/seed purposes you can still insert rows via a migration:

```sql
INSERT INTO categories (slug, label, sort_order) VALUES ('sports', 'Sports', 30);
```
