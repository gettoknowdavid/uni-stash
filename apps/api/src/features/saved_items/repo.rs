use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for a saved item: the listing id plus when it was saved.
/// The client hydrates full listing data via the existing listings
/// endpoints, so this stays deliberately minimal.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SavedItemResponse {
    pub listing_id: Uuid,
    #[serde(with = "time::serde::rfc3339")]
    pub saved_at: time::OffsetDateTime,
}

#[derive(Serialize)]
pub struct SavedItemsListResponse {
    pub items: Vec<SavedItemResponse>,
    pub next_cursor: Option<String>,
}

#[derive(Clone, Debug)]
pub struct SavedItemsRepo {
    db: sqlx::PgPool,
}

impl SavedItemsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Saves a listing for a user. Idempotent: re-saving an already-saved
    /// listing is a no-op (ON CONFLICT DO NOTHING), not an error.
    pub async fn save(&self, user_id: Uuid, listing_id: Uuid) -> Result<(), AppError> {
        sqlx::query!(
            "INSERT INTO saved_items (user_id, listing_id) VALUES ($1, $2)
             ON CONFLICT (user_id, listing_id) DO NOTHING",
            user_id,
            listing_id,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Removes a saved listing. Idempotent: unsaving something that isn't
    /// saved is a no-op, not an error.
    pub async fn unsave(&self, user_id: Uuid, listing_id: Uuid) -> Result<(), AppError> {
        sqlx::query!(
            "DELETE FROM saved_items WHERE user_id = $1 AND listing_id = $2",
            user_id,
            listing_id,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Whether a user has saved a listing.
    pub async fn is_saved(&self, user_id: Uuid, listing_id: Uuid) -> Result<bool, AppError> {
        let row = sqlx::query!(
            "SELECT EXISTS(SELECT 1 FROM saved_items WHERE user_id = $1 AND listing_id = $2) AS saved",
            user_id,
            listing_id,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(row.saved.unwrap_or(false))
    }

    /// All saved listing ids for a user, newest first, cursor-paginated on
    /// (created_at, listing_id). Dynamic filter-free query, so static SQL.
    pub async fn list_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_listing_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<SavedItemResponse>, AppError> {
        let rows = sqlx::query_as::<_, SavedItemResponse>(
            "SELECT listing_id, created_at AS saved_at FROM saved_items
             WHERE user_id = $1
               AND ($2::timestamptz IS NULL OR (created_at, listing_id) < ($2, $3::uuid))
             ORDER BY created_at DESC, listing_id DESC
             LIMIT $4",
        )
        .bind(user_id)
        .bind(before_created_at)
        .bind(before_listing_id)
        .bind(limit + 1)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }
}
