-- Extensions required by the uni_stash schema.
-- Runs automatically on first `docker compose up` via the entrypoint init.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";
