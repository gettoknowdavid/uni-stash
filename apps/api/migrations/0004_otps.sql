-- 0004_otps.sql
--
-- OTP (One-Time Password) table for:
--   - Email verification (replaces JWT-based verify-email tokens)
--   - Password reset (new feature)
--
-- Design decisions:
--   - `code` stores the SHA-256 hash of the 6-digit OTP, not the plaintext.
--     The plaintext is sent to the user via email and never stored.
--   - `type` distinguishes between verification and password reset flows,
--     so the same table serves both use cases.
--   - `used_at` provides single-use enforcement with an audit trail.
--   - A user can only have ONE active OTP per type at a time. Generating
--     a new OTP for the same type invalidates any previous one by setting
--     `used_at` on the old row (see repo logic).

CREATE TABLE otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('email_verify', 'password_reset')),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Speed up OTP lookups: the primary query path is "find by code + type"
-- (during verification), and "find active by user + type" (during invalidation).
CREATE INDEX idx_otps_code_type ON otps(code, type);
CREATE INDEX idx_otps_user_type ON otps(user_id, type);
