use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::reports::ReportsListResponse;
use crate::features::reports::repo::ReportResponse;

#[derive(Debug, Deserialize, Validate)]
pub struct CreateReportRequest {
    /// Why the listing is being reported. Optional (a flag with no comment
    /// is still actionable), but capped so it can't be used as free storage.
    #[validate(length(max = 1000))]
    pub reason: Option<String>,
}

// POST /api/v1/reports — flag a listing for moderation. Idempotent per
// (reporter, listing): re-reporting returns the existing report.
pub async fn create_report(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
    body: ValidatedJson<CreateReportRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let listing_id = path.into_inner();
    let report = state
        .reports_repo
        .create(user.id, listing_id, body.reason.clone())
        .await?
        .ok_or_else(|| AppError::NotFound("listing not found".into()))?;

    Ok(
        HttpResponse::Created().json(ApiResponse::<ReportResponse, ErrorBody>::success(
            report,
            "report submitted successfully",
        )),
    )
}

// GET /api/v1/reports/mine — the caller's own reports, newest first.
// Useful for the client to show "reported" state and for self-audit;
// the full moderation queue is an admin concern for a later phase.
#[derive(Deserialize)]
pub struct ReportsQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

// PATCH /api/v1/reports/{report_id} — update the reason on one of the
// caller's own reports. Only `open` reports are editable; moderation
// already reviewing/resolving one is locked.
pub async fn update_report(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
    body: ValidatedJson<CreateReportRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    match state
        .reports_repo
        .update_reason(user.id, path.into_inner(), body.reason.clone())
        .await?
    {
        // Not found or not owned — 404 (never leak existence).
        None => Err(AppError::NotFound("report not found".into())),
        Some(None) => Err(AppError::Conflict(
            "this report is already under review and can no longer be edited".into(),
        )),
        Some(Some(report)) => Ok(HttpResponse::Ok().json(
            ApiResponse::<ReportResponse, ErrorBody>::success(report, "report updated"),
        )),
    }
}

// DELETE /api/v1/reports/{report_id} — withdraw one of the caller's own
// reports. Only `open` reports can be withdrawn.
pub async fn delete_report(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    match state
        .reports_repo
        .delete_owned(user.id, path.into_inner())
        .await?
    {
        None => Err(AppError::NotFound("report not found".into())),
        Some(false) => Err(AppError::Conflict(
            "this report is already under review and can no longer be withdrawn".into(),
        )),
        Some(true) => Ok(HttpResponse::NoContent().finish()),
    }
}

pub async fn my_reports(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<ReportsQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let cursor = match &query.cursor {
        Some(raw) => Some(crate::core::cursor::decode_cursor(raw)?),
        None => None,
    };

    let rows = state
        .reports_repo
        .list_for_user(
            user.id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let has_more = rows.len() as i64 > limit;
    let mut rows = rows;
    if has_more {
        rows.truncate(limit as usize);
    }
    let next_cursor = has_more.then(|| {
        let last = rows.last().expect("has_more implies non-empty");
        crate::core::cursor::encode_cursor(&crate::core::cursor::Cursor {
            created_at: last.created_at,
            id: last.id,
        })
    });

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ReportsListResponse, ErrorBody>::success(
            ReportsListResponse {
                reports: rows,
                next_cursor,
            },
            "ok",
        )),
    )
}
