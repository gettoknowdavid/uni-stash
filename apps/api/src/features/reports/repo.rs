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

    /// Fetches one of the user's reports (ownership enforced in the WHERE).
    pub async fn find_owned(
        &self,
        user_id: Uuid,
        report_id: Uuid,
    ) -> Result<Option<ReportResponse>, AppError> {
        let row = sqlx::query_as::<_, ReportResponse>(
            "SELECT id, reporter_id, listing_id, reason, status, created_at
             FROM reports WHERE id = $1 AND reporter_id = $2",
        )
        .bind(report_id)
        .bind(user_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }

    /// Updates a report's reason. Returns `None` when the report doesn't
    /// exist or belongs to someone else; `Some((None, false))` means it
    /// exists but is no longer editable (moderation already picked it up).
    pub async fn update_reason(
        &self,
        user_id: Uuid,
        report_id: Uuid,
        reason: Option<String>,
    ) -> Result<Option<Option<ReportResponse>>, AppError> {
        let row = sqlx::query_as::<_, ReportResponse>(
            "UPDATE reports SET reason = $3
             WHERE id = $1 AND reporter_id = $2 AND status = 'open'
             RETURNING id, reporter_id, listing_id, reason, status, created_at",
        )
        .bind(report_id)
        .bind(user_id)
        .bind(reason)
        .fetch_optional(&self.db)
        .await?;

        if let Some(row_item) = row {
            return Ok(Some(Some(row_item)));
        }
        // Distinguish "not yours / doesn't exist" from "locked": re-read.
        match self.find_owned(user_id, report_id).await? {
            Some(_) => Ok(Some(None)),
            None => Ok(None),
        }
    }

    /// Deletes (withdraws) one of the user's reports. Reports already in
    /// moderation (`reviewing`/`resolved`/`dismissed`) are locked — the
    /// user may only withdraw `open` ones. Returns:
    /// `None` = not found / not owned, `Some(false)` = locked,
    /// `Some(true)` = deleted.
    pub async fn delete_owned(
        &self,
        user_id: Uuid,
        report_id: Uuid,
    ) -> Result<Option<bool>, AppError> {
        let result = sqlx::query(
            "DELETE FROM reports WHERE id = $1 AND reporter_id = $2 AND status = 'open'",
        )
        .bind(report_id)
        .bind(user_id)
        .execute(&self.db)
        .await?;
        if result.rows_affected() > 0 {
            return Ok(Some(true));
        }
        match self.find_owned(user_id, report_id).await? {
            Some(_) => Ok(Some(false)),
            None => Ok(None),
        }
    }

    // -----------------------------------------------------------------------
    // Admin moderation surface
    // -----------------------------------------------------------------------

    /// All listing reports, optionally filtered by status, oldest first
    /// (moderation works the backlog).
    pub async fn list_for_admin(
        &self,
        status: Option<&str>,
        limit: i64,
    ) -> Result<Vec<AdminReportRow>, AppError> {
        let rows = sqlx::query_as::<_, AdminReportRow>(
            "SELECT r.id, r.reporter_id, r.listing_id, l.title AS listing_title,
                    u.display_name AS reporter_name, r.reason, r.status, r.created_at
             FROM reports r
             JOIN listings l ON l.id = r.listing_id
             JOIN users u ON u.id = r.reporter_id
             WHERE ($1::text IS NULL OR r.status = $1)
             ORDER BY r.created_at ASC
             LIMIT $2",
        )
        .bind(status)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Set a listing report's moderation status.
    pub async fn set_status(
        &self,
        report_id: Uuid,
        status: &str,
    ) -> Result<Option<String>, AppError> {
        let row = sqlx::query_scalar::<_, String>(
            "UPDATE reports SET status = $2 WHERE id = $1 RETURNING status",
        )
        .bind(report_id)
        .bind(status)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }

    /// All user reports, optionally filtered by status, oldest first.
    pub async fn list_user_reports_for_admin(
        &self,
        status: Option<&str>,
        limit: i64,
    ) -> Result<Vec<AdminUserReportRow>, AppError> {
        let rows = sqlx::query_as::<_, AdminUserReportRow>(
            "SELECT ur.id, ur.reporter_id, ru.display_name AS reporter_name,
                    ur.reported_user_id, rdu.display_name AS reported_user_name,
                    ur.reason, ur.status, ur.created_at
             FROM user_reports ur
             JOIN users ru ON ru.id = ur.reporter_id
             JOIN users rdu ON rdu.id = ur.reported_user_id
             WHERE ($1::text IS NULL OR ur.status = $1)
             ORDER BY ur.created_at ASC
             LIMIT $2",
        )
        .bind(status)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Set a user report's moderation status.
    pub async fn set_user_report_status(
        &self,
        report_id: Uuid,
        status: &str,
    ) -> Result<Option<String>, AppError> {
        let row = sqlx::query_scalar::<_, String>(
            "UPDATE user_reports SET status = $2 WHERE id = $1 RETURNING status",
        )
        .bind(report_id)
        .bind(status)
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }
}

/// Admin wire shape for a listing report (denormalized names/titles).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminReportRow {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub reporter_name: String,
    pub listing_id: Uuid,
    pub listing_title: String,
    pub reason: Option<String>,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

/// Admin wire shape for a user report.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminUserReportRow {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub reporter_name: String,
    pub reported_user_id: Uuid,
    pub reported_user_name: String,
    pub reason: Option<String>,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}
