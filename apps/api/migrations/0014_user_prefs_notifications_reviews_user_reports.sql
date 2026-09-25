-- 0014_user_prefs_notifications_reviews_user_reports.sql
--
-- Four features in one migration (all additive, no destructive changes):
--
-- 1. USER PREFERENCES
--    users.email_notifications_enabled  — weekly digests / major updates
--    users.profile_visibility           — 'public' | 'private'
--      public  = other users can see the user's listings history
--      private = listings still browsable, but the profile page shows
--                minimal info to other users
--
-- 2. IN-APP NOTIFICATIONS INBOX
--    notifications: one row per user event (new chat message, sale, etc).
--    Written best-effort at the same points push notifications fire, so the
--    inbox works even when the device has no push token. `data` carries a
--    small JSON payload for deep-links (chat_id, listing_id, ...).
--
-- 3. RATINGS & REVIEWS
--    reviews: one review per (sale, author). The author must be the buyer
--    or the seller of the sale; the counterpart is the reviewee. 1..5
--    stars + optional text.
--
-- 4. USER REPORTS
--    user_reports: flags against a USER (not a listing). Reuses the same
--    open/reviewing/resolved/dismissed lifecycle as listings reports.

-- ---------------------------------------------------------------------------
-- 1. User preferences
-- ---------------------------------------------------------------------------
ALTER TABLE users
    ADD COLUMN email_notifications_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN profile_visibility TEXT NOT NULL DEFAULT 'public'
        CHECK (profile_visibility IN ('public', 'private'));

-- ---------------------------------------------------------------------------
-- 2. In-app notifications
-- ---------------------------------------------------------------------------
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Dotted type tag the client maps to an icon + route, e.g.
    -- 'chat.message', 'sale.completed'.
    type TEXT NOT NULL,

    -- Pre-formatted title/body so the inbox renders without joins.
    title TEXT NOT NULL,
    body TEXT NOT NULL,

    -- Deep-link payload: { "chat_id": "...", "listing_id": "..." }.
    -- NULL-able: not every notification deep-links anywhere.
    data JSONB,

    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Inbox scan: newest first per recipient; unread filter for badge counts.
CREATE INDEX idx_notifications_recipient
    ON notifications(recipient_id, created_at DESC);
CREATE INDEX idx_notifications_unread
    ON notifications(recipient_id) WHERE read_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Ratings & reviews
-- ---------------------------------------------------------------------------
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The completed sale being rated. RESTRICT: a review is a permanent
    -- record; deleting the listing must not erase the rating.
    sale_id UUID NOT NULL REFERENCES sale_history(id) ON DELETE RESTRICT,

    -- Author must be buyer or seller of the sale (enforced in the API
    -- layer; schema keeps a plain FK for integrity after user hard-delete).
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT CHECK (char_length(comment) <= 1000),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One review per author per sale.
    UNIQUE (sale_id, author_id)
);

-- Profile badge: average + count for a user.
CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);
-- "Have I already reviewed this sale?" lookups.
CREATE INDEX idx_reviews_author ON reviews(author_id, sale_id);

-- ---------------------------------------------------------------------------
-- 4. User reports (report a user, distinct from listing reports)
-- ---------------------------------------------------------------------------
CREATE TABLE user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- RESTRICT: moderation evidence must survive the reported user being
    -- hard-deleted (users are soft-deleted in practice anyway).
    reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    reason TEXT,

    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (reporter_id, reported_user_id)
);

CREATE INDEX idx_user_reports_status ON user_reports(status, created_at ASC);
CREATE INDEX idx_user_reports_reported ON user_reports(reported_user_id);
