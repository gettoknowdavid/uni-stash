-- 0007_photo_url.sql
--
-- Add optional photo URL to users. NULL means "no photo yet"
-- (clients should show initials as fallback).

ALTER TABLE users
    ADD COLUMN photo_url TEXT;
