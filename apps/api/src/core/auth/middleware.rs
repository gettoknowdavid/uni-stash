use std::future::ready;

use actix_web::{FromRequest, HttpRequest, dev::Payload, web};
use anyhow::anyhow;
use uuid::Uuid;

use crate::core::{auth::jwt, error::AppError, state::AppState};

#[derive(Clone, Debug, serde::Serialize)]
pub struct AuthUser {
    pub id: Uuid,
    pub email: String,
    pub email_verified: bool,
    pub display_name: String,
}
impl FromRequest for AuthUser {
    type Error = AppError;
    type Future = std::future::Ready<Result<Self, AppError>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        let app_state = match req.app_data::<web::Data<AppState>>() {
            Some(state) => state,
            None => {
                return ready(Err(AppError::Internal(anyhow!(
                    "AppState missing from request"
                ))));
            }
        };

        let header = match req.headers().get("Authorization") {
            Some(value) => value,
            None => {
                return ready(Err(AppError::Unauthorized(
                    "missing authorization header".to_string(),
                )));
            }
        };
        let header_str = match header.to_str() {
            Ok(value) => value,
            Err(_) => {
                return ready(Err(AppError::Unauthorized(
                    "invalid header encoding".to_string(),
                )));
            }
        };
        if !header_str.starts_with("Bearer ") {
            return ready(Err(AppError::Unauthorized(
                "malformed authorization header".to_string(),
            )));
        }

        let token = &header_str[7..]; // safe: we already checked starts_with("Bearer ")
        if token.is_empty() {
            return ready(Err(AppError::Unauthorized(
                "empty bearer token".to_string(),
            )));
        }

        let claims = match jwt::verify_access_token(&app_state.jwt_keys, token) {
            Ok(claims) => claims,
            Err(e) => return ready(Err(e)),
        };

        ready(Ok(AuthUser {
            id: claims.sub,
            email: claims.email,
            email_verified: claims.email_verified,
            display_name: claims.display_name,
        }))
    }
}
