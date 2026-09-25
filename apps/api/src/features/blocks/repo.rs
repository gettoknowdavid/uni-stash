use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for a blocked user: the user plus when the block was made.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BlockedUserResponse {
    pub blocked_id: Uuid,
    pub display_name: String,
    pub photo_url: Option<String>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

#[derive(Clone, Debug)]
pub struct BlocksRepo {
    db: sqlx::PgPool,
}

impl BlocksRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Block [blocker] → [blocked]. Idempotent (ON CONFLICT DO NOTHING);
    /// the CHECK constraint rejects self-blocks. Returns true when a new
    /// row was created.
    pub async fn block(&self, blocker: Uuid, blocked: Uuid) -> Result<bool, AppError> {
        let result = sqlx::query!(
            "INSERT INTO user_blocks (blocker_id, blocked_id)
             VALUES ($1, $2)
             ON CONFLICT (blocker_id, blocked_id) DO NOTHING",
            blocker,
            blocked,
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    /// Remove a block. Returns true when a row was deleted.
    pub async fn unblock(&self, blocker: Uuid, blocked: Uuid) -> Result<bool, AppError> {
        let result = sqlx::query!(
            "DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2",
            blocker,
            blocked,
        )
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    /// The caller's block list, newest first.
    pub async fn blocked_users(&self, blocker: Uuid) -> Result<Vec<BlockedUserResponse>, AppError> {
        let rows = sqlx::query_as::<_, BlockedUserResponse>(
            "SELECT b.blocked_id, u.display_name, u.photo_url, b.created_at
             FROM user_blocks b
             JOIN users u ON u.id = b.blocked_id
             WHERE b.blocker_id = $1
             ORDER BY b.created_at DESC",
        )
        .bind(blocker)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Is [blocked] blocked by [blocker]?
    pub async fn is_blocked(&self, blocker: Uuid, blocked: Uuid) -> Result<bool, AppError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2)",
        )
        .bind(blocker)
        .bind(blocked)
        .fetch_one(&self.db)
        .await?;
        Ok(exists)
    }

    /// Bidirectional check: has either user blocked the other?
    pub async fn blocked_either_way(&self, a: Uuid, b: Uuid) -> Result<bool, AppError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(
                 SELECT 1 FROM user_blocks
                 WHERE (blocker_id = $1 AND blocked_id = $2)
                    OR (blocker_id = $2 AND blocked_id = $1)
             )",
        )
        .bind(a)
        .bind(b)
        .fetch_one(&self.db)
        .await?;
        Ok(exists)
    }

    /// All user IDs that [user_id] has blocked (for listing-feed filters).
    pub async fn blocked_ids_by(&self, user_id: Uuid) -> Result<Vec<Uuid>, AppError> {
        let rows = sqlx::query_scalar::<_, Uuid>(
            "SELECT blocked_id FROM user_blocks WHERE blocker_id = $1",
        )
        .bind(user_id)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }
}
