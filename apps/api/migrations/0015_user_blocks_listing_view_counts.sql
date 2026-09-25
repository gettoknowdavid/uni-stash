-- 0015_user_blocks_listing_view_counts.sql
--
-- Two additive features:
--
-- 1. USER BLOCKS
--    user_blocks: blocker hides a user. Enforced server-side:
--      * chats: blocked pairs cannot exchange messages (or create new chats)
--      * listings: blocked users' listings are hidden from browse/search
--    One direction only (blocking is asymmetric), UNIQUE per pair.
--
-- 2. LISTING VIEW COUNTS
--    listings.view_count: incremented on detail fetches by non-owners.
--    Exposed on the detail response.

-- ---------------------------------------------------------------------------
-- 1. User blocks
-- ---------------------------------------------------------------------------
CREATE TABLE user_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A user cannot block themselves (CHECK) and can only block the same
    -- person once (UNIQUE pair).
    CHECK (blocker_id <> blocked_id),
    PRIMARY KEY (blocker_id, blocked_id)
);

-- "Have I blocked this user?" lookups + the blocked-list page.
CREATE INDEX idx_user_blocks_blocker ON user_blocks(blocker_id, created_at DESC);
-- Enforcement joins filter listings/chats by the blocked side.
CREATE INDEX idx_user_blocks_blocked ON user_blocks(blocked_id);

-- ---------------------------------------------------------------------------
-- 2. Listing view counts
-- ---------------------------------------------------------------------------
ALTER TABLE listings ADD COLUMN view_count BIGINT NOT NULL DEFAULT 0;
