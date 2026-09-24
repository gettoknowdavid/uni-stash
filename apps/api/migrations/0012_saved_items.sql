-- 0012_saved_items.sql
--
-- Server-side saved (bookmarked) listings. One row per (user, listing):
-- a user either saved a listing or they didn't, so the unique constraint
-- doubles as an idempotency guard for double-taps and retried requests.
--
-- WHY THIS TABLE EXISTS:
--   "Saved Items" was previously device-local (secure storage), which
--   meant bookmarks didn't survive reinstalls and never synced across
--   devices. Persisting them server-side makes them portable.
--
-- DELETION SEMANTICS:
--   ON DELETE CASCADE on both FKs: an account deletion wipes that user's
--   bookmarks, and a hard-deleted listing disappears from everyone's
--   saved list. (Listings are soft-deleted in practice, so the listing
--   cascade is a belt-and-braces path.)

CREATE TABLE saved_items (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, listing_id)
);

-- Newest-first listing of a user's saved items.
CREATE INDEX idx_saved_items_user ON saved_items(user_id, created_at DESC);
