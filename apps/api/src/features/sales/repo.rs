use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for a sale record. Built from a JOIN so the response carries
/// listing title + counterpart display names without extra round-trips.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SaleResponse {
    pub id: Uuid,
    pub listing_id: Uuid,
    pub buyer_id: Option<Uuid>,
    pub seller_id: Uuid,
    /// Minor units (kobo for NGN); None for barter sales.
    pub price: Option<i64>,
    pub currency: Option<String>,
    pub barter_request: Option<String>,
    /// Listing title, denormalized for display.
    pub listing_title: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

#[derive(Clone, Debug)]
pub struct SalesRepo {
    db: sqlx::PgPool,
}

impl SalesRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Purchases = sales where the user was the buyer, newest first,
    /// cursor-paginated on (created_at, id).
    pub async fn purchases_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<SaleResponse>, AppError> {
        self.list_for_user("buyer_id", user_id, before_created_at, before_id, limit)
            .await
    }

    /// Sales = sales where the user was the seller, newest first.
    pub async fn sales_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<SaleResponse>, AppError> {
        self.list_for_user("seller_id", user_id, before_created_at, before_id, limit)
            .await
    }

    async fn list_for_user(
        &self,
        column: &str,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<SaleResponse>, AppError> {
        // Two separate static-SQL branches keep the query string a
        // compile-time-known &'static str (sqlx 0.9 rejects dynamic SQL).
        let rows = if column == "buyer_id" {
            sqlx::query_as::<_, SaleResponse>(
                "SELECT s.id, s.listing_id, s.buyer_id, s.seller_id, s.price, s.currency::TEXT AS currency, s.barter_request, l.title AS listing_title, s.created_at FROM sale_history s JOIN listings l ON l.id = s.listing_id WHERE s.buyer_id = $1 AND ($2::timestamptz IS NULL OR (s.created_at, s.id) < ($2, $3::uuid)) ORDER BY s.created_at DESC, s.id DESC LIMIT $4",
            )
            .bind(user_id)
            .bind(before_created_at)
            .bind(before_id)
            .bind(limit + 1)
            .fetch_all(&self.db)
            .await?
        } else {
            sqlx::query_as::<_, SaleResponse>(
                "SELECT s.id, s.listing_id, s.buyer_id, s.seller_id, s.price, s.currency::TEXT AS currency, s.barter_request, l.title AS listing_title, s.created_at FROM sale_history s JOIN listings l ON l.id = s.listing_id WHERE s.seller_id = $1 AND ($2::timestamptz IS NULL OR (s.created_at, s.id) < ($2, $3::uuid)) ORDER BY s.created_at DESC, s.id DESC LIMIT $4",
            )
            .bind(user_id)
            .bind(before_created_at)
            .bind(before_id)
            .bind(limit + 1)
            .fetch_all(&self.db)
            .await?
        };
        Ok(rows)
    }
}
