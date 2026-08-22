use crate::{
    core::{
        auth::{admin_jwt, refresh_token as rt},
        clients::JwtKeys,
        error::AppError,
    },
    features::admin_auth::models::{Admin, AdminProfile, AdminRefreshToken},
};

/// Grace window for refresh-token reuse after a legitimate rotation.
/// Same reasoning as the student flow's REUSE_GRACE_WINDOW_SECONDS.
const REUSE_GRACE_WINDOW_SECONDS: i64 = 5;

#[derive(Clone, Debug)]
pub struct AdminAuthRepo {
    db: sqlx::PgPool,
}

impl AdminAuthRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    // -----------------------------------------------------------------------
    // Admin lookup
    // -----------------------------------------------------------------------

    pub async fn find_admin_by_email(&self, email: &str) -> Result<Option<Admin>, AppError> {
        let admin = sqlx::query_as!(Admin, "SELECT * FROM admins WHERE email = $1", email)
            .fetch_optional(&self.db)
            .await?;
        Ok(admin)
    }

    pub async fn find_admin_by_id(&self, id: &uuid::Uuid) -> Result<Option<Admin>, AppError> {
        let admin = sqlx::query_as!(Admin, "SELECT * FROM admins WHERE id = $1", id)
            .fetch_optional(&self.db)
            .await?;
        Ok(admin)
    }

    pub async fn find_admin_profile_by_id(
        &self,
        admin_id: &uuid::Uuid,
    ) -> Result<Option<AdminProfile>, AppError> {
        let profile = sqlx::query_as!(
            AdminProfile,
            "SELECT id, email, display_name, level, permissions, is_active
             FROM admins WHERE id = $1",
            admin_id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(profile)
    }

    // -----------------------------------------------------------------------
    // Refresh tokens
    // -----------------------------------------------------------------------

    pub async fn issue_admin_refresh_token<'e, E>(
        &self,
        executor: E,
        admin_id: uuid::Uuid,
        family_id: uuid::Uuid,
    ) -> Result<(String, uuid::Uuid), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        let plain = rt::generate_refresh_token_plain();
        let hash = rt::hash_refresh_token(&plain);
        let expires_at =
            time::OffsetDateTime::now_utc() + time::Duration::days(rt::REFRESH_TOKEN_TTL_DAYS);

        let id = sqlx::query_scalar!(
            "INSERT INTO admin_refresh_tokens (admin_id, token_hash, family_id, expires_at)
             VALUES ($1, $2, $3, $4)
             RETURNING id",
            admin_id,
            &hash,
            family_id,
            expires_at,
        )
        .fetch_one(executor)
        .await?;

        Ok((plain, id))
    }

    pub async fn revoke_admin_refresh_token<'e, E>(
        &self,
        executor: E,
        token_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE admin_refresh_tokens SET revoked = true, revoked_at = now() WHERE id = $1",
            token_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    pub async fn supersede_admin_refresh_token<'e, E>(
        &self,
        executor: E,
        old_token_id: uuid::Uuid,
        new_token_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE admin_refresh_tokens SET superseded_by = $1 WHERE id = $2",
            new_token_id,
            old_token_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    pub async fn find_admin_refresh_token_by_hash(
        &self,
        token_hash: &str,
    ) -> Result<Option<AdminRefreshToken>, AppError> {
        let token = sqlx::query_as!(
            AdminRefreshToken,
            "SELECT * FROM admin_refresh_tokens WHERE token_hash = $1",
            token_hash
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(token)
    }

    pub async fn find_admin_refresh_token_by_id(
        &self,
        token_id: uuid::Uuid,
    ) -> Result<Option<AdminRefreshToken>, AppError> {
        let token = sqlx::query_as!(
            AdminRefreshToken,
            "SELECT * FROM admin_refresh_tokens WHERE id = $1",
            token_id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(token)
    }

    /// Idempotent: returns Ok(()) even if the token is unknown or already revoked.
    pub async fn revoke_admin_refresh_token_by_hash(
        &self,
        presented_plain: &str,
    ) -> Result<(), AppError> {
        let hash = rt::hash_refresh_token(presented_plain);
        sqlx::query!(
            "UPDATE admin_refresh_tokens SET revoked = true, revoked_at = now()
             WHERE token_hash = $1 AND revoked = false",
            hash,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Revoke every non-revoked token for the given admin across all families.
    ///
    /// Called after a successful admin password reset — kills every existing
    /// session for that admin, not just the one that triggered the reset.
    /// This is stricter than the student flow, which doesn't currently do this;
    /// the higher blast radius per admin account justifies the difference.
    pub async fn revoke_all_admin_tokens(&self, admin_id: uuid::Uuid) -> Result<(), AppError> {
        sqlx::query!(
            "UPDATE admin_refresh_tokens SET revoked = true, revoked_at = now()
             WHERE admin_id = $1 AND revoked = false",
            admin_id,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    pub async fn revoke_admin_family_tokens<'e, E>(
        &self,
        executor: E,
        family_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE admin_refresh_tokens SET revoked = true, revoked_at = now()
             WHERE family_id = $1 AND revoked = false",
            family_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    pub async fn begin(&self) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AppError> {
        Ok(self.db.begin().await?)
    }

    // -----------------------------------------------------------------------
    // OTP management (password reset)
    // -----------------------------------------------------------------------

    /// Generate a new OTP for the given admin.
    ///
    /// Invalidates any existing active `password_reset` OTP for this admin,
    /// then inserts the fresh one. Returns the plaintext code (for emailing)
    /// and the row id.
    pub async fn insert_admin_otp(
        &self,
        admin_id: uuid::Uuid,
    ) -> Result<(String, uuid::Uuid), AppError> {
        use crate::core::auth::otp;

        let mut tx = self.db.begin().await?;

        // Invalidate any existing active password_reset OTP for this admin
        sqlx::query!(
            "UPDATE admin_otps SET used_at = now()
             WHERE admin_id = $1 AND type = 'password_reset' AND used_at IS NULL",
            admin_id,
        )
        .execute(&mut *tx)
        .await?;

        // Generate and store the new OTP
        let plain = otp::generate_otp();
        let code_hash = otp::hash_otp(&plain);
        let expires_at =
            time::OffsetDateTime::now_utc() + time::Duration::minutes(otp::OTP_TTL_MINUTES);

        let id = sqlx::query_scalar!(
            "INSERT INTO admin_otps (admin_id, code, type, expires_at)
             VALUES ($1, $2, 'password_reset', $3)
             RETURNING id",
            admin_id,
            &code_hash,
            expires_at,
        )
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok((plain, id))
    }

    /// Verify a password_reset OTP for an admin.
    ///
    /// Returns the `admin_id` on success. Checks:
    /// 1. Code matches a stored hash
    /// 2. Not expired
    /// 3. Not already used
    ///
    /// Marks the OTP as used atomically.
    pub async fn verify_admin_otp(&self, code: &str) -> Result<uuid::Uuid, AppError> {
        use crate::core::auth::otp;

        let code_hash = otp::hash_otp(code);
        let now = time::OffsetDateTime::now_utc();

        let mut tx = self.db.begin().await?;

        let row = sqlx::query!(
            "SELECT id, admin_id, expires_at
             FROM admin_otps
             WHERE code = $1 AND type = 'password_reset' AND used_at IS NULL AND expires_at > $2
             FOR UPDATE",
            &code_hash,
            now,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let row = match row {
            Some(r) => r,
            None => {
                drop(tx);
                return Err(AppError::BadRequest("invalid or expired OTP".into()));
            }
        };

        // Mark as used
        sqlx::query!(
            "UPDATE admin_otps SET used_at = now() WHERE id = $1",
            row.id,
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(row.admin_id)
    }

    /// Update an admin's password hash.
    pub async fn update_admin_password_hash(
        &self,
        admin_id: &uuid::Uuid,
        new_hash: &str,
    ) -> Result<(), AppError> {
        sqlx::query!(
            "UPDATE admins SET password_hash = $1, updated_at = now() WHERE id = $2",
            new_hash,
            admin_id,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Rotation helpers (mirrors AuthRepo)
    // -----------------------------------------------------------------------

    pub async fn rotate_admin_from_row(
        &self,
        keys: &JwtKeys,
        row: &AdminRefreshToken,
    ) -> Result<(String, String, i64), AppError> {
        let mut tx = self.db.begin().await?;

        self.revoke_admin_refresh_token(&mut *tx, row.id).await?;
        let (new_plain, new_id) = self
            .issue_admin_refresh_token(&mut *tx, row.admin_id, row.family_id)
            .await?;
        self.supersede_admin_refresh_token(&mut *tx, row.id, new_id)
            .await?;

        tx.commit().await?;

        let admin = self.find_admin_by_id(&row.admin_id).await?.ok_or_else(|| {
            AppError::Internal(anyhow::anyhow!(
                "admin refresh token references deleted admin {}",
                row.admin_id
            ))
        })?;

        let access_token = admin_jwt::sign_admin_access_token(keys, admin.id, &admin.level)?;
        Ok((access_token, new_plain, 900))
    }

    pub async fn handle_reused_admin_token(
        &self,
        keys: &JwtKeys,
        row: &AdminRefreshToken,
    ) -> Result<(String, String, i64), AppError> {
        let now = time::OffsetDateTime::now_utc();

        let within_grace = row
            .revoked_at
            .map(|t| now.unix_timestamp() - t.unix_timestamp() <= REUSE_GRACE_WINDOW_SECONDS)
            .unwrap_or(false)
            && row.superseded_by.is_some();

        if within_grace {
            let superseding_id = row.superseded_by.unwrap();
            let superseding_row = self
                .find_admin_refresh_token_by_id(superseding_id)
                .await?
                .ok_or_else(|| {
                    AppError::Internal(anyhow::anyhow!(
                        "superseding token {} not found for family {}",
                        superseding_id,
                        row.family_id
                    ))
                })?;

            return self.rotate_admin_from_row(keys, &superseding_row).await;
        }

        tracing::warn!(
            family_id = %row.family_id,
            token_id = %row.id,
            "admin refresh token family revoked: reuse detected outside grace window"
        );
        self.revoke_admin_family_tokens(&self.db, row.family_id)
            .await?;

        Err(AppError::Unauthorized(
            "refresh token reuse detected".into(),
        ))
    }

    // -----------------------------------------------------------------------
    // Cleanup (same pattern as student flow)
    // -----------------------------------------------------------------------

    pub async fn cleanup_expired_admin_refresh_tokens(&self) -> Result<u64, AppError> {
        let result = sqlx::query!("DELETE FROM admin_refresh_tokens WHERE expires_at < now()")
            .execute(&self.db)
            .await?;
        Ok(result.rows_affected())
    }

    pub async fn cleanup_old_admin_revoked_tokens(
        &self,
        older_than_secs: i64,
    ) -> Result<u64, AppError> {
        let cutoff =
            time::OffsetDateTime::now_utc() - time::SignedDuration::seconds(older_than_secs);
        let result = sqlx::query!(
            "DELETE FROM admin_refresh_tokens WHERE revoked = true AND revoked_at < $1",
            cutoff,
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }

    pub async fn cleanup_expired_admin_otps(&self) -> Result<u64, AppError> {
        let result = sqlx::query!(
            "DELETE FROM admin_otps
             WHERE expires_at < now()
                OR (used_at IS NOT NULL AND used_at < now() - interval '24 hours')"
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }
}
