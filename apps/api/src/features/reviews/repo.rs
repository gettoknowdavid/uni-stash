use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for a review, with denormalized display names so the client
/// renders without extra round-trips.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ReviewResponse {
    pub id: Uuid,
    pub sale_id: Uuid,
    pub author_id: Uuid,
    pub reviewee_id: Uuid,
    pub rating: i16,
    pub comment: Option<String>,
    /// Display name of the author ("Ada L.").
    pub author_name: String,
    /// Display name of the reviewed user.
    pub reviewee_name: String,
    pub listing_title: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

/// Average rating + count for a user's profile badge.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RatingSummary {
    /// NULL when the user has no reviews yet.
    pub average_rating: Option<f64>,
    pub review_count: i64,
}

#[derive(Clone, Debug)]
pub struct ReviewsRepo {
    db: sqlx::PgPool,
}

impl ReviewsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Insert a review. Caller must have validated:
    /// - author is buyer or seller of the sale,
    /// - reviewee is the counterpart,
    /// - author hasn't already reviewed this sale.
    ///
    /// Returns the created row.
    pub async fn create(
        &self,
        sale_id: Uuid,
        author_id: Uuid,
        reviewee_id: Uuid,
        rating: i16,
        comment: Option<String>,
    ) -> Result<ReviewResponse, AppError> {
        let row = sqlx::query_as::<_, ReviewResponse>(
            "INSERT INTO reviews (sale_id, author_id, reviewee_id, rating, comment)
             VALUES ($1, $2, $3, $4, $5)
             RETURNING r.id, r.sale_id, r.author_id, r.reviewee_id, r.rating, r.comment,
                       a.display_name AS author_name, b.display_name AS reviewee_name,
                       l.title AS listing_title, r.created_at",
        )
        .bind(sale_id)
        .bind(author_id)
        .bind(reviewee_id)
        .bind(rating)
        .bind(comment)
        .fetch_one(&self.db)
        .await?;
        Ok(row)
    }

    /// All reviews ABOUT a user (their rating wall), newest first.
    pub async fn for_user(
        &self,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<ReviewResponse>, AppError> {
        let rows = sqlx::query_as::<_, ReviewResponse>(
            "SELECT r.id, r.sale_id, r.author_id, r.reviewee_id, r.rating, r.comment,
                    a.display_name AS author_name, b.display_name AS reviewee_name,
                    l.title AS listing_title, r.created_at
             FROM reviews r
             JOIN users a ON a.id = r.author_id
             JOIN users b ON b.id = r.reviewee_id
             JOIN sale_history s ON s.id = r.sale_id
             JOIN listings l ON l.id = s.listing_id
             WHERE r.reviewee_id = $1
             ORDER BY r.created_at DESC
             LIMIT $2",
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Average + count for the profile badge.
    pub async fn summary_for_user(&self, user_id: Uuid) -> Result<RatingSummary, AppError> {
        let row = sqlx::query_as::<_, RatingSummary>(
            "SELECT AVG(rating)::FLOAT8 AS average_rating, COUNT(*) AS review_count
             FROM reviews WHERE reviewee_id = $1",
        )
        .bind(user_id)
        .fetch_one(&self.db)
        .await?;
        Ok(row)
    }

    /// The user's own review for a sale (to prevent duplicates client-side).
    pub async fn find_for_sale(
        &self,
        sale_id: Uuid,
        author_id: Uuid,
    ) -> Result<Option<ReviewResponse>, AppError> {
        let row = sqlx::query_as::<_, ReviewResponse>(
            "SELECT r.id, r.sale_id, r.author_id, r.reviewee_id, r.rating, r.comment,
                    a.display_name AS author_name, b.display_name AS reviewee_name,
                    l.title AS listing_title, r.created_at
             FROM reviews r
             JOIN users a ON a.id = r.author_id
             JOIN users b ON b.id = r.reviewee_id
             JOIN sale_history s ON s.id = r.sale_id
             JOIN listings l ON l.id = s.listing_id
             WHERE r.sale_id = $1 AND r.author_id = $2",
        )
        .bind(sale_id)
        .bind(author_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }

    /// Look up a sale and confirm [author_id] is a participant. Returns
    /// (sale_id, reviewee_id) — the counterpart — or None when the sale
    /// doesn't exist.
    pub async fn sale_counterpart(
        &self,
        sale_id: Uuid,
        author_id: Uuid,
    ) -> Result<Option<Uuid>, AppError> {
        let row = sqlx::query_scalar::<_, Uuid>(
            "SELECT CASE WHEN buyer_id = $2 THEN seller_id ELSE buyer_id END
             FROM sale_history
             WHERE id = $1 AND ($2 = buyer_id OR $2 = seller_id)",
        )
        .bind(sale_id)
        .bind(author_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }
}
