-- 0009_deletion_warning_level.sql
--
-- Tracks which pre-deletion warning emails have been sent for
-- soft-deleted accounts, so the background job doesn't spam users.
--
-- Levels:
--   0 = no warning sent yet
--   1 = 7-day warning sent
--   2 = 1-day warning sent

ALTER TABLE users
    ADD COLUMN deletion_warning_level SMALLINT NOT NULL DEFAULT 0;
