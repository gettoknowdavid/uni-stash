use uuid::Uuid;

use crate::core::error::AppError;

#[derive(Clone, Debug)]
pub struct NotificationsRepo {
    db: sqlx::PgPool,
}

impl NotificationsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Upsert a device token for a user. Uses ON CONFLICT to handle
    /// re-registration of the same token (e.g. app restart).
    pub async fn upsert_device_token(
        &self,
        user_id: Uuid,
        token: &str,
        platform: &str,
    ) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO device_tokens (user_id, token, platform)
             VALUES ($1, $2, $3)
             ON CONFLICT (user_id, token) DO UPDATE SET platform = EXCLUDED.platform, created_at = now()",
        )
        .bind(user_id)
        .bind(token)
        .bind(platform)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Delete a specific device token (e.g. on logout).
    pub async fn remove_device_token(&self, user_id: Uuid, token: &str) -> Result<(), AppError> {
        sqlx::query("DELETE FROM device_tokens WHERE user_id = $1 AND token = $2")
            .bind(user_id)
            .bind(token)
            .execute(&self.db)
            .await?;
        Ok(())
    }

    /// Delete all device tokens for a user (e.g. on account deletion).
    pub async fn remove_all_tokens(&self, user_id: Uuid) -> Result<(), AppError> {
        sqlx::query("DELETE FROM device_tokens WHERE user_id = $1")
            .bind(user_id)
            .execute(&self.db)
            .await?;
        Ok(())
    }
}
