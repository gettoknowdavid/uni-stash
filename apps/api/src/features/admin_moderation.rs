use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::core::{
    auth::middleware::AdminSession,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::reports::repo::{AdminReportRow, AdminUserReportRow};
use crate::features::reviews::repo::ReviewResponse;

/// Admin moderation routes — mounted under /api/v1/admin alongside the
/// existing admin_management routes; all guarded by `AdminSession`.
pub fn configure(cfg: &mut actix_web::web::ServiceConfig) {
    cfg.service(
        actix_web::web::scope("/admin/moderation")
            .route("/reports", actix_web::web::get().to(list_reports))
            .route(
                "/reports/{report_id}",
                actix_web::web::patch().to(update_report),
            )
            .route("/user-reports", actix_web::web::get().to(list_user_reports))
            .route(
                "/user-reports/{report_id}",
                actix_web::web::patch().to(update_user_report),
            )
            .route("/reviews", actix_web::web::get().to(list_reviews))
            .route(
                "/reviews/{review_id}",
                actix_web::web::delete().to(delete_review),
            ),
    );
}

const REPORT_STATUSES: [&str; 4] = ["open", "reviewing", "resolved", "dismissed"];

#[derive(Deserialize)]
pub struct ModerationQueueQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct ModerationStatusRequest {
    #[validate(length(min = 1, max = 20))]
    pub status: String,
}

fn validate_status(status: &str) -> Result<(), AppError> {
    if !REPORT_STATUSES.contains(&status) {
        return Err(AppError::BadRequest(format!(
            "status must be one of: {}",
            REPORT_STATUSES.join(", ")
        )));
    }
    Ok(())
}

/// GET /api/v1/admin/moderation/reports — listing-report moderation queue.
pub async fn list_reports(
    _admin: AdminSession,
    state: web::Data<AppState>,
    query: web::Query<ModerationQueueQuery>,
) -> Result<HttpResponse, AppError> {
    if let Some(ref status) = query.status {
        validate_status(status)?;
    }
    let rows = state
        .reports_repo
        .list_for_admin(
            query.status.as_deref(),
            query.limit.unwrap_or(50).clamp(1, 200),
        )
        .await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<Vec<AdminReportRow>, ErrorBody>::success(
            rows, "ok",
        )),
    )
}

/// PATCH /api/v1/admin/moderation/reports/{id} — set a listing report's status.
pub async fn update_report(
    admin: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    body: ValidatedJson<ModerationStatusRequest>,
) -> Result<HttpResponse, AppError> {
    let report_id = path.into_inner();
    validate_status(&body.status)?;

    let new_status = state
        .reports_repo
        .set_status(report_id, &body.status)
        .await?
        .ok_or_else(|| AppError::NotFound("report not found".into()))?;

    let _ = admin; // audit logging could go here; status change is the contract for now
    Ok(
        HttpResponse::Ok().json(ApiResponse::<serde_json::Value, ErrorBody>::success(
            serde_json::json!({ "id": report_id, "status": new_status }),
            "report updated",
        )),
    )
}

/// GET /api/v1/admin/moderation/user-reports — user-report moderation queue.
pub async fn list_user_reports(
    _admin: AdminSession,
    state: web::Data<AppState>,
    query: web::Query<ModerationQueueQuery>,
) -> Result<HttpResponse, AppError> {
    if let Some(ref status) = query.status {
        validate_status(status)?;
    }
    let rows = state
        .reports_repo
        .list_user_reports_for_admin(
            query.status.as_deref(),
            query.limit.unwrap_or(50).clamp(1, 200),
        )
        .await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<Vec<AdminUserReportRow>, ErrorBody>::success(
            rows, "ok",
        )),
    )
}

/// PATCH /api/v1/admin/moderation/user-reports/{id} — set a user report's status.
pub async fn update_user_report(
    _admin: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    body: ValidatedJson<ModerationStatusRequest>,
) -> Result<HttpResponse, AppError> {
    let report_id = path.into_inner();
    validate_status(&body.status)?;

    let new_status = state
        .reports_repo
        .set_user_report_status(report_id, &body.status)
        .await?
        .ok_or_else(|| AppError::NotFound("user report not found".into()))?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<serde_json::Value, ErrorBody>::success(
            serde_json::json!({ "id": report_id, "status": new_status }),
            "user report updated",
        )),
    )
}

/// GET /api/v1/admin/moderation/reviews — newest reviews (moderation queue).
pub async fn list_reviews(
    _admin: AdminSession,
    state: web::Data<AppState>,
) -> Result<HttpResponse, AppError> {
    let rows = state.reviews_repo.list_for_admin(100).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<Vec<ReviewResponse>, ErrorBody>::success(
            rows, "ok",
        )),
    )
}

/// DELETE /api/v1/admin/moderation/reviews/{id} — remove an abusive review.
pub async fn delete_review(
    _admin: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let review_id = path.into_inner();
    let deleted = state.reviews_repo.admin_delete(review_id).await?;
    if !deleted {
        return Err(AppError::NotFound("review not found".into()));
    }
    Ok(HttpResponse::NoContent().finish())
}
