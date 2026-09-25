use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;
use crate::features::listings::dtos::ListingSummaryRow;

/// Wire shape for a saved item: the id + when it was saved, plus the
/// hydrated listing summary so the client can render the card without a
/// per-item detail fetch. Rows whose listing was deleted (FK cascade) or
/// hidden drop out of the JOIN naturally.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SavedItemResponse {
    pub listing_id: Uuid,
    #[serde(with = "time::serde::rfc3339")]
    pub saved_at: time::OffsetDateTime,
    #[sqlx(flatten)]
    pub listing: ListingSummaryRow,
}

#[derive(Serialize)]
pub struct SavedItemsListResponse {
    pub listings: Vec<crate::features::listings::dtos::ListingSummary>,
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

    /// The user's saved listings, newest first, cursor-paginated on
    /// (created_at, listing_id), each hydrated with the listing summary
    /// fields the client's card grid needs. Sold listings stay visible
    /// (the client renders a SOLD badge); deleted listings drop out via
    /// the INNER JOIN.
    pub async fn list_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_listing_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<SavedItemResponse>, AppError> {
        let rows = sqlx::query_as::<_, SavedItemResponse>(
            "SELECT si.listing_id, si.created_at AS saved_at,
                    l.id, l.title, l.price, l.currency::TEXT AS currency,
                    l.barter_request, l.condition, l.status, l.created_at
             FROM saved_items si
             JOIN listings l ON l.id = si.listing_id
             WHERE si.user_id = $1
               AND ($2::timestamptz IS NULL OR (si.created_at, si.listing_id) < ($2, $3::uuid))
             ORDER BY si.created_at DESC, si.listing_id DESC
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
