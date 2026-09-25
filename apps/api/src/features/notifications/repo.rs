use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for one in-app notification.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct NotificationResponse {
    pub id: Uuid,
    pub recipient_id: Uuid,
    /// Dotted type tag the client maps to an icon + route
    /// (e.g. `chat.message`, `sale.completed`).
    #[serde(rename = "type")]
    pub notification_type: String,
    pub title: String,
    pub body: String,
    /// Deep-link payload (chat_id, listing_id, ...) — a JSON object.
    pub data: Option<serde_json::Value>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub read_at: Option<time::OffsetDateTime>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

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

    // -----------------------------------------------------------------------
    // In-app notifications inbox
    // -----------------------------------------------------------------------

    /// Insert one in-app notification. Best-effort by callers: inbox
    /// delivery must never fail the originating action (a chat message
    /// send, a sale, ...).
    #[allow(clippy::too_many_arguments)]
    pub async fn insert_notification(
        &self,
        recipient_id: Uuid,
        notification_type: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO notifications (recipient_id, type, title, body, data)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(recipient_id)
        .bind(notification_type)
        .bind(title)
        .bind(body)
        .bind(data)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// The user's inbox, newest first, cursor-paginated.
    pub async fn list_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<NotificationResponse>, AppError> {
        let rows = sqlx::query_as::<_, NotificationResponse>(
            "SELECT id, recipient_id, type, title, body, data, read_at, created_at
             FROM notifications
             WHERE recipient_id = $1
               AND ($2::timestamptz IS NULL OR (created_at, id) < ($2, $3::uuid))
             ORDER BY created_at DESC, id DESC
             LIMIT $4",
        )
        .bind(user_id)
        .bind(before_created_at)
        .bind(before_id)
        .bind(limit + 1)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Number of unread notifications (for the badge).
    pub async fn unread_count(&self, user_id: Uuid) -> Result<i64, AppError> {
        let count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM notifications WHERE recipient_id = $1 AND read_at IS NULL",
        )
        .bind(user_id)
        .fetch_one(&self.db)
        .await?;
        Ok(count)
    }

    /// Marks a single notification read (owned by [user_id]). Returns
    /// false when the row doesn't exist or isn't owned (never leaks
    /// existence — callers map this to 404).
    pub async fn mark_read(&self, user_id: Uuid, notification_id: Uuid) -> Result<bool, AppError> {
        let result = sqlx::query(
            "UPDATE notifications SET read_at = now()
             WHERE id = $1 AND recipient_id = $2 AND read_at IS NULL",
        )
        .bind(notification_id)
        .bind(user_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    /// Marks every unread notification read. Returns how many changed.
    pub async fn mark_all_read(&self, user_id: Uuid) -> Result<u64, AppError> {
        let result = sqlx::query(
            "UPDATE notifications SET read_at = now()
             WHERE recipient_id = $1 AND read_at IS NULL",
        )
        .bind(user_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }

    /// Deletes one notification (owned by [user_id]). Same 404 semantics
    /// as [mark_read].
    pub async fn delete(&self, user_id: Uuid, notification_id: Uuid) -> Result<bool, AppError> {
        let result = sqlx::query(
            "DELETE FROM notifications WHERE id = $1 AND recipient_id = $2",
        )
        .bind(notification_id)
        .bind(user_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }
}
