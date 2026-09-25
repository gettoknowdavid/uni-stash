use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::core::cursor::{Cursor, decode_cursor};
use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::notifications::repo::NotificationResponse;

#[derive(Debug, Deserialize, validator::Validate)]
pub struct RegisterDeviceRequest {
    /// The push notification token from the OS (APNs / FCM) or Beams SDK.
    #[validate(length(min = 1, max = 512))]
    pub token: String,

    /// Platform identifier: "ios", "android", or "web".
    #[validate(length(min = 1, max = 20))]
    pub platform: String,
}

/// POST /api/v1/notifications/register-device
///
/// Stores the device's push notification token. Idempotent — re-registering
/// the same token updates the platform field.
pub async fn register_device(
    state: web::Data<AppState>,
    user: AuthUser,
    body: ValidatedJson<RegisterDeviceRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let platform = body.platform.to_lowercase();
    if !["ios", "android", "web"].contains(&platform.as_str()) {
        return Err(AppError::ValidationError {
            field: "platform".into(),
            reason: "must be 'ios', 'android', or 'web'".into(),
        });
    }

    state
        .notifications_repo
        .upsert_device_token(user.id, &body.token, &platform)
        .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "device registered",
        )),
    )
}

// ---------------------------------------------------------------------------
// In-app notifications inbox
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct InboxQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(serde::Serialize)]
pub struct InboxResponse {
    pub notifications: Vec<NotificationResponse>,
    pub next_cursor: Option<String>,
    pub unread_count: i64,
}

/// GET /api/v1/notifications — the caller's inbox, newest first.
pub async fn list_notifications(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<InboxQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let cursor = match &query.cursor {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let mut rows = state
        .notifications_repo
        .list_for_user(
            user.id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let has_more = rows.len() as i64 > limit;
    if has_more {
        rows.truncate(limit as usize);
    }
    let next_cursor = has_more.then(|| {
        let last = rows.last().expect("has_more implies non-empty");
        crate::core::cursor::encode_cursor(&Cursor {
            created_at: last.created_at,
            id: last.id,
        })
    });

    let unread_count = state.notifications_repo.unread_count(user.id).await?;

    Ok(HttpResponse::Ok().json(
        ApiResponse::<InboxResponse, ErrorBody>::success(
            InboxResponse {
                notifications: rows,
                next_cursor,
                unread_count,
            },
            "ok",
        ),
    ))
}

/// GET /api/v1/notifications/unread-count — lightweight badge poll.
pub async fn unread_count(
    state: web::Data<AppState>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let count = state.notifications_repo.unread_count(user.id).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<i64, ErrorBody>::success(
            count,
            "ok",
        )),
    )
}

/// POST /api/v1/notifications/{id}/read — mark one notification read.
pub async fn mark_read(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let updated = state
        .notifications_repo
        .mark_read(user.id, path.into_inner())
        .await?;
    if !updated {
        return Err(AppError::NotFound("notification not found".into()));
    }
    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "notification marked read",
        )),
    )
}

/// POST /api/v1/notifications/read-all — mark everything read.
pub async fn mark_all_read(
    state: web::Data<AppState>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let updated = state.notifications_repo.mark_all_read(user.id).await?;
    Ok(HttpResponse::Ok().json(
        ApiResponse::<u64, ErrorBody>::success(updated, "all notifications marked read"),
    ))
}

/// DELETE /api/v1/notifications/{id} — remove one notification.
pub async fn delete_notification(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let deleted = state
        .notifications_repo
        .delete(user.id, path.into_inner())
        .await?;
    if !deleted {
        return Err(AppError::NotFound("notification not found".into()));
    }
    Ok(HttpResponse::NoContent().finish())
}
