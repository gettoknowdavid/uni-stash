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

// ---------------------------------------------------------------------------
// AdminUser extractor — re-reads role from DB, never trusts JWT claims
// ---------------------------------------------------------------------------

/// Wrapper around `AuthUser` that confirms the caller has `role = 'admin'`
/// by querying the `users` table on every request.
///
/// Per TRD §2.5.1: the role check for admin-only endpoints re-reads from the
/// DB rather than trusting a JWT claim, so a demoted admin loses access
/// immediately even if their access token hasn't expired yet.
#[derive(Clone, Debug)]
pub struct AdminUser {
    pub inner: AuthUser,
}

impl FromRequest for AdminUser {
    type Error = AppError;
    type Future =
        std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, AppError>> + Send>>;

    fn from_request(req: &HttpRequest, payload: &mut Payload) -> Self::Future {
        // Extract AuthUser (validates JWT) and clone the DB pool before
        // entering the async block, so we don't hold &HttpRequest across
        // an await point (HttpRequest is not Sync).
        let auth_user_fut = AuthUser::from_request(req, payload);
        let db = req.app_data::<web::Data<AppState>>().map(|s| s.db.clone());

        Box::pin(async move {
            let auth_user = auth_user_fut.await?;
            let db = db.ok_or_else(|| AppError::Internal(anyhow!("AppState missing")))?;

            // Re-read role from DB — this is the security-critical step.
            // Per TRD §2.5.1: role check re-reads from DB rather than
            // trusting a JWT claim, so a demoted admin loses access
            // immediately even if their access token hasn't expired.
            let role = sqlx::query_scalar!("SELECT role FROM users WHERE id = $1", auth_user.id,)
                .fetch_optional(&db)
                .await
                .map_err(AppError::from)?
                .ok_or_else(|| AppError::NotFound("user not found".into()))?;

            if role != "admin" {
                return Err(AppError::Forbidden);
            }

            Ok(AdminUser { inner: auth_user })
        })
    }
}
