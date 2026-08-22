-- 0005_admins.sql
--
-- Admin system, fully independent of schools/users. Admins are a separate
-- principal — no school_id, no FK into the students/marketplace graph, no
-- email domain restriction (an admin can be admin@gmail.com just as validly
-- as admin@uniport.edu.ng). Auth is a parallel rotation-token system to
-- refresh_tokens, kept in its own table so a compromised student session
-- can never be confused with, or escalate into, admin capability.

CREATE TABLE admins (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           CITEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    level           TEXT NOT NULL DEFAULT 'standard' CHECK (level IN ('super', 'standard')),
    permissions     JSONB NOT NULL DEFAULT '{}',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_by      UUID REFERENCES admins(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Refresh tokens: same rotation/reuse-detection shape as refresh_tokens
-- (0001_auth.sql) — family_id + superseded_by, single-use, sliding expiry.
CREATE TABLE admin_refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id        UUID NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL,
    family_id       UUID NOT NULL,
    revoked         BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ,
    superseded_by   UUID REFERENCES admin_refresh_tokens(id),
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admin_refresh_tokens_admin ON admin_refresh_tokens(admin_id);
CREATE INDEX idx_admin_refresh_tokens_family ON admin_refresh_tokens(family_id);
CREATE UNIQUE INDEX idx_admin_refresh_tokens_hash ON admin_refresh_tokens(token_hash);

-- Audit log: who did what to which admin/school/etc. admin_id is nullable
-- (ON DELETE SET NULL) so a deactivated admin's history survives them.
CREATE TABLE admin_audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id        UUID REFERENCES admins(id) ON DELETE SET NULL,
    action          TEXT NOT NULL,
    target_type     TEXT,
    target_id       TEXT,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admin_audit_admin ON admin_audit_log(admin_id, created_at DESC);

-- admin_otps — mirrors otps (0004_otps.sql) exactly, scoped to admins instead
-- of users. Kept as a separate table rather than reusing `otps` with a
-- nullable user_id/admin_id pair: same reasoning as admin_refresh_tokens vs
-- refresh_tokens — no shared blast radius, no query has to remember which
-- FK is populated for which row.
CREATE TABLE admin_otps (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id        UUID NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
    code            TEXT NOT NULL,
    type            TEXT NOT NULL CHECK (type IN ('password_reset')),
    expires_at      TIMESTAMPTZ NOT NULL,
    used_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admin_otps_code_type ON admin_otps(code, type);
CREATE INDEX idx_admin_otps_admin_type ON admin_otps(admin_id, type);
