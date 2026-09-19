-- 0008_user_soft_delete.sql
--
-- Soft-delete support for user accounts (GDPR Article 17 compliance).
--
-- `deleted_at`        — timestamp when the user requested account deletion.
--                       NULL means the account is active.
-- `deletion_scheduled_at` — when the account should be hard-deleted
--                           (deleted_at + 30 days).  The background job
--                           checks this column, not deleted_at directly,
--                           so the grace period is explicit and tunable.

ALTER TABLE users
    ADD COLUMN deleted_at TIMESTAMPTZ,
    ADD COLUMN deletion_scheduled_at TIMESTAMPTZ;

-- Partial index: only soft-deleted users (active users have NULL).
-- Speeds up the background-job query that scans for expired deletions.
CREATE INDEX idx_users_deletion_scheduled
    ON users (deletion_scheduled_at)
    WHERE deleted_at IS NOT NULL;
