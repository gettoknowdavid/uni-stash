use serde::Serialize;
use uuid::Uuid;

use crate::core::error::AppError;

/// Wire shape for a report as seen by its reporter.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ReportResponse {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub listing_id: Uuid,
    pub reason: Option<String>,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

#[derive(Clone, Debug)]
pub struct ReportsRepo {
    db: sqlx::PgPool,
}

impl ReportsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Creates a report. Idempotent per (reporter, listing): re-reporting
    /// the same listing returns the existing row unchanged, so double-taps
    /// and retries neither duplicate nor error. Returns `None` when the
    /// listing doesn't exist (the INSERT...SELECT matched nothing).
    pub async fn create(
        &self,
        reporter_id: Uuid,
        listing_id: Uuid,
        reason: Option<String>,
    ) -> Result<Option<ReportResponse>, AppError> {
        let row = sqlx::query_as::<_, ReportResponse>(
            "WITH inserted AS (
                 INSERT INTO reports (reporter_id, listing_id, reason)
                 SELECT $1, $2, $3
                 WHERE EXISTS (SELECT 1 FROM listings WHERE id = $2)
                 ON CONFLICT (reporter_id, listing_id) DO NOTHING
                 RETURNING id, reporter_id, listing_id, reason, status, created_at
             ), existing AS (
                 SELECT id, reporter_id, listing_id, reason, status, created_at
                 FROM reports
                 WHERE reporter_id = $1 AND listing_id = $2
             )
             SELECT * FROM inserted
             UNION ALL
             SELECT * FROM existing
             LIMIT 1",
        )
        .bind(reporter_id)
        .bind(listing_id)
        .bind(reason)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }

    /// The user's own reports, newest first, cursor-paginated.
    pub async fn list_for_user(
        &self,
        user_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<ReportResponse>, AppError> {
        let rows = sqlx::query_as::<_, ReportResponse>(
            "SELECT id, reporter_id, listing_id, reason, status, created_at
             FROM reports
             WHERE reporter_id = $1
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
}
