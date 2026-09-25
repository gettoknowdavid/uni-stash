use actix_web::{HttpResponse, web};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct UserReportResponse {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub reported_user_id: Uuid,
    pub reason: Option<String>,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct CreateUserReportRequest {
    /// Why the user is being reported. Optional, capped at 1000 chars.
    #[validate(length(max = 1000))]
    pub reason: Option<String>,
}

/// POST /api/v1/reports/users/{user_id} — flag a user for moderation.
/// Idempotent per (reporter, reported user); self-reports are rejected.
pub async fn create_user_report(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
    body: ValidatedJson<CreateUserReportRequest>,
) -> Result<HttpResponse, AppError> {
    let reported_user_id = path.into_inner();
    if reported_user_id == user.id {
        return Err(AppError::BadRequest("you cannot report yourself".into()));
    }

    // The reported user must exist (and not be soft-deleted).
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)",
    )
    .bind(reported_user_id)
    .fetch_one(&state.db)
    .await?;
    if !exists {
        return Err(AppError::NotFound("user not found".into()));
    }

    let report = sqlx::query_as::<_, UserReportResponse>(
        "WITH inserted AS (
             INSERT INTO user_reports (reporter_id, reported_user_id, reason)
             SELECT $1, $2, $3
             ON CONFLICT (reporter_id, reported_user_id) DO NOTHING
             RETURNING id, reporter_id, reported_user_id, reason, status, created_at
         ), existing AS (
             SELECT id, reporter_id, reported_user_id, reason, status, created_at
             FROM user_reports
             WHERE reporter_id = $1 AND reported_user_id = $2
         )
         SELECT * FROM inserted
         UNION ALL
         SELECT * FROM existing
         LIMIT 1",
    )
    .bind(user.id)
    .bind(reported_user_id)
    .bind(body.reason.clone())
    .fetch_one(&state.db)
    .await?;

    Ok(
        HttpResponse::Created().json(ApiResponse::<UserReportResponse, ErrorBody>::success(
            report,
            "report submitted successfully",
        )),
    )
}
