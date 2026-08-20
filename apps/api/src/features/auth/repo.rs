use crate::{
    core::{auth::refresh_token, error::AppError},
    features::auth::{
        dtos::InsertUserInput,
        models::{RefreshToken, School, User},
    },
};

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

    /// Begin a new database transaction.
    pub async fn begin(&self) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AppError> {
        Ok(self.db.begin().await?)
    }
}
