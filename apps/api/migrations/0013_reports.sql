-- 0013_reports.sql
--
-- User reports (flags) against listings. One row per (reporter, listing):
-- re-reporting the same listing by the same user is idempotent
-- (ON CONFLICT DO NOTHING, like saved_items).
--
-- HISTORY: a `reports` table already exists from 0003_chats.sql with an
-- earlier, unused shape (no created_at, nullable listing_id,
-- reported_user_id, status check without 'reviewing', reason NOT NULL).
-- It has no production rows (feature never shipped), so this migration
-- replaces it with the shape the reports feature expects. Dropping also
-- removes 0003's stale index, recreated below with the new columns.

DROP TABLE IF EXISTS reports;

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- The flagged listing. RESTRICT (not CASCADE): a report is a moderation
    -- record; hard-deleting the flagged listing should not silently erase
    -- the evidence. (Listings are soft-deleted in practice.)
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,

    -- Free-text reason from the reporter, validated (1..1000 chars) at the
    -- API layer. NULL-able in the schema so future programmatic reports
    -- (e.g. auto-flags) can omit it.
    reason TEXT,

    -- open | reviewing | resolved | dismissed. Admin lifecycle; new rows
    -- always start 'open'. The MVP API only creates + lets the reporter
    -- edit/withdraw 'open' rows — status changes come with the admin
    -- moderation surface.
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (reporter_id, listing_id)
);

-- Moderation queue scan: oldest unresolved first.
CREATE INDEX idx_reports_status ON reports(status, created_at ASC);
-- Per-listing report count (abuse signal).
CREATE INDEX idx_reports_listing ON reports(listing_id);
