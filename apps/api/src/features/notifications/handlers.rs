use actix_web::{HttpResponse, web};
use serde::Deserialize;
use validator::Validate;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};

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
