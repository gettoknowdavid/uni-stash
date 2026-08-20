#!/usr/bin/env bash
# scripts/dev-db.sh — Spin up local Postgres, run migrations, generate sqlx offline cache.
#
# Usage:
#   ./scripts/dev-db.sh          # full setup (start + migrate + offline cache)
#   ./scripts/dev-db.sh start    # just start postgres
#   ./scripts/dev-db.sh migrate  # run migrations only
#   ./scripts/dev-db.sh prepare  # regenerate .sqlx/ offline cache
#   ./scripts/dev-db.sh stop     # stop postgres
#   ./scripts/dev-db.sh reset    # stop, delete volume, restart fresh
#
# Prerequisites: docker, cargo-sqlx (`cargo install sqlx-cli --no-default-features --features postgres`)

set -euo pipefail

cd "$(dirname "$0")/.."

DB_URL="postgres://postgres:postgres@localhost:5432/uni_stash"
export DATABASE_URL="$DB_URL"

cmd="${1:-full}"

start_db() {
  echo "▶ Starting PostgreSQL 16..."
  docker compose up -d postgres

  echo "▶ Waiting for health check..."
  local retries=30
  until docker compose exec -T postgres pg_isready -U postgres -d uni_stash &>/dev/null; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "✗ Postgres did not become ready in time."
      exit 1
    fi
    sleep 1
  done
  echo "✓ PostgreSQL is ready."
}

run_migrations() {
  echo "▶ Running migrations..."
  # Explicit URL since .env may point to a remote DB (NeonDB etc.)
  sqlx migrate run --source apps/api/migrations --database-url "$DB_URL"
  echo "✓ Migrations applied."
}

prepare_offline() {
  echo "▶ Generating .sqlx/ offline cache..."
  # Must use local Postgres, not NeonDB's PgBouncer — PgBouncer in
  # transaction mode doesn't support the named prepared statements
  # that cargo sqlx prepare needs.
  cargo sqlx prepare --workspace --database-url "$DB_URL"
  echo "✓ Offline cache written to apps/api/.sqlx/"
}

case "$cmd" in
  full)
    start_db
    run_migrations
    prepare_offline
    echo ""
    echo "✓ Dev database is ready. DATABASE_URL=$DB_URL"
    ;;
  start)
    start_db
    ;;
  migrate)
    run_migrations
    ;;
  prepare)
    prepare_offline
    ;;
  stop)
    echo "▶ Stopping PostgreSQL..."
    docker compose down
    echo "✓ Stopped."
    ;;
  reset)
    echo "▶ Resetting database (stop + delete volume + restart)..."
    docker compose down -v
    start_db
    run_migrations
    prepare_offline
    echo "✓ Database reset complete."
    ;;
  *)
    echo "Usage: $0 {full|start|migrate|prepare|stop|reset}"
    exit 1
    ;;
esac
