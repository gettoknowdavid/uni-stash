use crate::{
    core::{auth::refresh_token, error::AppError},
    features::auth::{
        dtos::{InsertUserInput, UserProfile},
        models::{RefreshToken, School, User},
    },
};

/// Grace window for refresh-token reuse after a legitimate rotation.
///
/// If a client re-presents a token that was *just* revoked as part of a
/// normal rotation (within this window), we treat it as a duplicate request
/// and rotate from the *current* valid token instead of revoking the whole
/// family.  Tunable — 5 seconds covers network retries without opening a
/// meaningful attack surface.
const REUSE_GRACE_WINDOW_SECONDS: i64 = 5;

#[derive(Clone, Debug)]
pub struct AuthRepo {
    db: sqlx::PgPool,
}

impl AuthRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    pub async fn find_school_by_domain(&self, email: &str) -> Result<Option<School>, AppError> {
        if !email.contains("@") {
            return Err(AppError::BadRequest("invalid email".to_string()));
        }
        let domain = email.split("@").last().unwrap_or("");
        let school = sqlx::query_as!(School, "SELECT * FROM schools WHERE domain = $1", domain)
            .fetch_optional(&self.db)
            .await?;
        Ok(school)
    }

    pub async fn insert_user<'a>(&self, input: &InsertUserInput<'a>) -> Result<User, AppError> {
        let user = sqlx::query_as!(
            User,
            r#"INSERT INTO users (school_id, email, password_hash, display_name)
            VALUES ($1, $2, $3, $4)
            RETURNING *"#,
            input.school_id,
            input.email,
            input.password,
            input.display_name,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(user)
    }

    pub async fn mark_email_verified(&self, user_id: &uuid::Uuid) -> Result<(), AppError> {
        sqlx::query!(
            "UPDATE users SET email_verified = true WHERE id = $1",
            user_id
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    pub async fn find_user_by_email(&self, email: &str) -> Result<Option<User>, AppError> {
        let user = sqlx::query_as!(User, "SELECT * FROM users WHERE email = $1", email)
            .fetch_optional(&self.db)
            .await?;
        Ok(user)
    }

    /// Update a user's password hash. Used by the password reset flow.
    pub async fn update_password_hash(
        &self,
        user_id: &uuid::Uuid,
        new_hash: &str,
    ) -> Result<(), AppError> {
        sqlx::query!(
            "UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2",
            new_hash,
            user_id,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    pub async fn find_user_by_id(&self, user_id: &uuid::Uuid) -> Result<Option<User>, AppError> {
        let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", user_id)
            .fetch_optional(&self.db)
            .await?;
        Ok(user)
    }

    /// Issues a new refresh token for `user_id` within the given `family_id`.
    ///
    /// Returns `(plain_token, row_id)` — the plaintext value goes to the client;
    /// only the SHA-256 hash is stored in `refresh_tokens.token_hash`.
    ///
    /// Accepts any sqlx [`Executor`], so the caller decides the transactional
    /// boundary:
    ///
    /// * **`&pool`** — CM-3.6 fresh login: no transaction needed, single insert.
    /// * **`&mut tx`** — CM-3.7 rotation: same transaction as revoke-old-token
    ///   write, guaranteeing atomicity.
    pub async fn issue_refresh_token<'e, E>(
        &self,
        executor: E,
        user_id: uuid::Uuid,
        family_id: uuid::Uuid,
    ) -> Result<(String, uuid::Uuid), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        let plain = refresh_token::generate_refresh_token_plain();
        let hash = refresh_token::hash_refresh_token(&plain);
        let expires_at = time::OffsetDateTime::now_utc()
            + time::Duration::days(refresh_token::REFRESH_TOKEN_TTL_DAYS);

        let id = sqlx::query_scalar!(
            "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
             VALUES ($1, $2, $3, $4)
             RETURNING id",
            user_id,
            &hash,
            family_id,
            expires_at,
        )
        .fetch_one(executor)
        .await?;

        Ok((plain, id))
    }

    /// Mark a refresh token as revoked and record the revocation timestamp.
    pub async fn revoke_refresh_token<'e, E>(
        &self,
        executor: E,
        token_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE refresh_tokens SET revoked = true, revoked_at = now() WHERE id = $1",
            token_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    /// Link `superseded_by` on the old token to point to the new token.
    pub async fn supersede_refresh_token<'e, E>(
        &self,
        executor: E,
        old_token_id: uuid::Uuid,
        new_token_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE refresh_tokens SET superseded_by = $1 WHERE id = $2",
            new_token_id,
            old_token_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    pub async fn find_refresh_token_by_hash(
        &self,
        token_hash: &str,
    ) -> Result<Option<RefreshToken>, AppError> {
        let token = sqlx::query_as!(
            RefreshToken,
            "SELECT * FROM refresh_tokens WHERE token_hash = $1",
            token_hash
        )
        .fetch_optional(&self.db)
        .await?;

        Ok(token)
    }

    /// Revoke a refresh token by its plaintext value (hashed internally).
    ///
    /// Idempotent: returns `Ok(())` even if the token is unknown or already
    /// revoked — this satisfies the logout idempotency AC.
    pub async fn revoke_refresh_token_by_hash(
        &self,
        presented_plain: &str,
    ) -> Result<(), AppError> {
        let hash = refresh_token::hash_refresh_token(presented_plain);
        sqlx::query!(
            "UPDATE refresh_tokens SET revoked = true, revoked_at = now()
             WHERE token_hash = $1 AND revoked = false",
            hash,
        )
        .execute(&self.db)
        .await?;
        // Idempotent: 0 rows affected is fine (unknown or already revoked).
        Ok(())
    }

    /// Fetch the slim profile for GET /auth/me.
    ///
    /// Returns `None` if the user was deleted (shouldn't happen for a
    /// valid JWT, but defensive).
    pub async fn find_user_profile_by_id(
        &self,
        user_id: &uuid::Uuid,
    ) -> Result<Option<UserProfile>, AppError> {
        let profile = sqlx::query_as!(
            UserProfile,
            "SELECT id, email, display_name, email_verified, role
             FROM users WHERE id = $1",
            user_id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(profile)
    }

    /// Fetch the slim profile by converting a [`User`] row.
    pub fn user_to_profile(user: &User) -> UserProfile {
        UserProfile {
            id: user.id,
            email: user.email.clone(),
            display_name: user.display_name.clone(),
            email_verified: user.email_verified,
            role: user.role.clone(),
        }
    }

    pub async fn find_refresh_token_by_id(
        &self,
        token_id: uuid::Uuid,
    ) -> Result<Option<RefreshToken>, AppError> {
        let token = sqlx::query_as!(
            RefreshToken,
            "SELECT * FROM refresh_tokens WHERE id = $1",
            token_id
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(token)
    }

    /// Revoke every non-revoked token in the given family.
    ///
    /// Called when reuse is detected outside the grace window — indicates
    /// possible token theft, so the entire family is nuked as a precaution.
    pub async fn revoke_family_tokens<'e, E>(
        &self,
        executor: E,
        family_id: uuid::Uuid,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'e, Database = sqlx::Postgres>,
    {
        sqlx::query!(
            "UPDATE refresh_tokens SET revoked = true, revoked_at = now()
             WHERE family_id = $1 AND revoked = false",
            family_id,
        )
        .execute(executor)
        .await?;
        Ok(())
    }

    /// Begin a new database transaction.
    /// Begin a new database transaction.
    pub async fn begin(&self) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AppError> {
        Ok(self.db.begin().await?)
    }

    /// Delete all refresh tokens that have passed their expiry.
    ///
    /// Called by the background cleanup job (CM-3.10).  Returns the number
    /// of rows deleted so the job can log it.
    pub async fn cleanup_expired_refresh_tokens(&self) -> Result<u64, AppError> {
        let result = sqlx::query!("DELETE FROM refresh_tokens WHERE expires_at < now()")
            .execute(&self.db)
            .await?;
        Ok(result.rows_affected())
    }

    // ------------------------------------------------------------------
    // OTP management
    // ------------------------------------------------------------------

    /// Generate a new OTP for the given user and type.
    ///
    /// Invalidates any existing active OTP of the same type for this user
    /// by setting `used_at` on the old row. Returns the plaintext OTP code
    /// (to be sent via email) and the OTP row ID.
    pub async fn insert_otp(
        &self,
        user_id: uuid::Uuid,
        otp_type: &str,
    ) -> Result<(String, uuid::Uuid), AppError> {
        use crate::core::auth::otp;

        let mut tx = self.db.begin().await?;

        // Invalidate any existing active OTP of this type for this user
        sqlx::query!(
            "UPDATE otps SET used_at = now()
             WHERE user_id = $1 AND type = $2 AND used_at IS NULL",
            user_id,
            otp_type,
        )
        .execute(&mut *tx)
        .await?;

        // Generate and store the new OTP
        let plain = otp::generate_otp();
        let code_hash = otp::hash_otp(&plain);
        let expires_at =
            time::OffsetDateTime::now_utc() + time::Duration::minutes(otp::OTP_TTL_MINUTES);

        let id = sqlx::query_scalar!(
            "INSERT INTO otps (user_id, code, type, expires_at)
             VALUES ($1, $2, $3, $4)
             RETURNING id",
            user_id,
            &code_hash,
            otp_type,
            expires_at,
        )
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok((plain, id))
    }

    /// Verify an OTP code for the given type.
    ///
    /// Returns the `user_id` on success. Checks:
    /// 1. Code matches a stored hash
    /// 2. Not expired
    /// 3. Not already used
    ///
    /// Marks the OTP as used atomically.
    pub async fn verify_otp(&self, code: &str, otp_type: &str) -> Result<uuid::Uuid, AppError> {
        use crate::core::auth::otp;

        let code_hash = otp::hash_otp(code);
        let now = time::OffsetDateTime::now_utc();

        let mut tx = self.db.begin().await?;

        // Find the OTP: must match code + type, not be expired, not be used
        let row = sqlx::query!(
            "SELECT id, user_id, expires_at
             FROM otps
             WHERE code = $1 AND type = $2 AND used_at IS NULL AND expires_at > $3
             FOR UPDATE",
            &code_hash,
            otp_type,
            now,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let row = match row {
            Some(r) => r,
            None => {
                let _ = tx.rollback().await;
                return Err(AppError::BadRequest("invalid or expired OTP".into()));
            }
        };

        // Mark as used
        sqlx::query!("UPDATE otps SET used_at = now() WHERE id = $1", row.id,)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;
        Ok(row.user_id)
    }

    /// Delete expired OTPs and OTPs used more than 24 hours ago.
    ///
    /// Called by the background cleanup job. Returns rows deleted.
    pub async fn cleanup_expired_otps(&self) -> Result<u64, AppError> {
        let result = sqlx::query!(
            "DELETE FROM otps
             WHERE expires_at < now()
                OR (used_at IS NOT NULL AND used_at < now() - interval '24 hours')"
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }

    pub async fn cleanup_old_revoked_tokens(&self, older_than_secs: i64) -> Result<u64, AppError> {
        let cutoff =
            time::OffsetDateTime::now_utc() - time::SignedDuration::seconds(older_than_secs);
        let result = sqlx::query!(
            "DELETE FROM refresh_tokens WHERE revoked = true AND revoked_at < $1",
            cutoff,
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }

    // ------------------------------------------------------------------
    // CM-3.7 / CM-3.8 orchestration helpers
    // ------------------------------------------------------------------

    /// Core rotation logic: revoke the presented row, issue a new token in
    /// the same family, link superseded_by, fetch the user, sign a fresh
    /// access token.  Used by both the happy path (CM-3.7) and the
    /// grace-window retry path (CM-3.8).
    pub async fn rotate_from_row(
        &self,
        keys: &crate::core::clients::JwtKeys,
        row: &RefreshToken,
    ) -> Result<(String, String, i64, UserProfile), AppError> {
        let mut tx = self.db.begin().await?;

        self.revoke_refresh_token(&mut *tx, row.id).await?;
        let (new_plain, new_id) = self
            .issue_refresh_token(&mut *tx, row.user_id, row.family_id)
            .await?;
        self.supersede_refresh_token(&mut *tx, row.id, new_id)
            .await?;

        tx.commit().await?;

        let user = self.find_user_by_id(&row.user_id).await?.ok_or_else(|| {
            AppError::Internal(anyhow::anyhow!(
                "refresh token references deleted user {}",
                row.user_id
            ))
        })?;

        let access_token = crate::core::auth::jwt::sign_access_token(keys, &user)?;
        let profile = Self::user_to_profile(&user);
        Ok((access_token, new_plain, 900, profile))
    }

    /// Handle reuse of an already-revoked token.
    ///
    /// Called from the refresh handler when `row.revoked == true`.
    ///
    /// * **Within grace window** (+ has a superseding token): treat as a
    ///   legitimate duplicate request.  Rotate from the *current* valid
    ///   token (the one that superseded the presented token) so the client
    ///   gets a fresh pair without an error.
    /// * **Outside grace window** (or no superseding link): treat as
    ///   potential compromise.  Revoke the entire family and reject.
    pub async fn handle_reused_token(
        &self,
        keys: &crate::core::clients::JwtKeys,
        row: &RefreshToken,
    ) -> Result<(String, String, i64, UserProfile), AppError> {
        let now = time::OffsetDateTime::now_utc();

        // Within grace = revoked_at is set, within the window, AND the token
        // has a superseding link (proving it was properly rotated, not just
        // revoked for some other reason).
        let within_grace = row
            .revoked_at
            .map(|t| now.unix_timestamp() - t.unix_timestamp() <= REUSE_GRACE_WINDOW_SECONDS)
            .unwrap_or(false)
            && row.superseded_by.is_some();

        if within_grace {
            // Legitimate retry: rotate from the CURRENT valid token in this
            // family, not from the stale one the client presented.
            let superseding_id = row.superseded_by.unwrap();
            let superseding_row = self
                .find_refresh_token_by_id(superseding_id)
                .await?
                .ok_or_else(|| {
                    AppError::Internal(anyhow::anyhow!(
                        "superseding token {} not found for family {}",
                        superseding_id,
                        row.family_id
                    ))
                })?;

            return self.rotate_from_row(keys, &superseding_row).await;
        }

        // Outside grace / no valid superseding link — compromise response.
        // Revoke every token sharing this family_id.
        tracing::warn!(
            family_id = %row.family_id,
            token_id = %row.id,
            "refresh token family revoked: reuse detected outside grace window"
        );
        self.revoke_family_tokens(&self.db, row.family_id).await?;

        Err(AppError::Unauthorized(
            "refresh token reuse detected".into(),
        ))
    }
}
