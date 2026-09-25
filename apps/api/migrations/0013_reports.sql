-- 0013_reports.sql
--
-- User reports (flags) against listings. One row per (reporter, listing):
-- re-reporting the same listing by the same user is idempotent
-- (ON CONFLICT DO NOTHING, like saved_items).
--
-- WHY THIS TABLE EXISTS:
--   The mobile app has shipped a "Report this listing" dialog since the
--   detail page landed, but it only showed a local toast — nothing was
--   persisted and nobody could review anything. This table gives
--   moderation a durable queue; the admin_management feature can list and
--   act on reports in a later phase.

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
    -- always start 'open'. The MVP API only creates rows — status changes
    -- come with the admin moderation surface.
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (reporter_id, listing_id)
);

-- Moderation queue scan: oldest unresolved first.
CREATE INDEX idx_reports_status ON reports(status, created_at ASC);
-- Per-listing report count (abuse signal).
CREATE INDEX idx_reports_listing ON reports(listing_id);
