use std::future::ready;

use actix_web::{FromRequest, HttpRequest, dev::Payload, web};
use anyhow::anyhow;
use uuid::Uuid;

use crate::core::{auth::admin_jwt, auth::jwt, error::AppError, state::AppState};

// ---------------------------------------------------------------------------
// AdminLevel enum
// ---------------------------------------------------------------------------

/// Represents an admin's authorization level. Informational in JWT claims;
/// every admin-gated action re-reads this from the DB to avoid trusting
/// stale token data.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum AdminLevel {
    Super,
    Standard,
}

impl std::fmt::Display for AdminLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AdminLevel::Super => write!(f, "super"),
            AdminLevel::Standard => write!(f, "standard"),
        }
    }
}

impl From<String> for AdminLevel {
    fn from(s: String) -> Self {
        match s.as_str() {
            "super" => AdminLevel::Super,
            _ => AdminLevel::Standard,
        }
    }
}

// ---------------------------------------------------------------------------
// AuthUser extractor — unchanged
// ---------------------------------------------------------------------------

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
// AdminSession extractor — validates admin JWT, re-reads is_active/level
// from DB on every request
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct AdminSession {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub level: AdminLevel,
    pub permissions: serde_json::Value,
    pub is_active: bool,
}

impl AdminSession {
    /// Check whether this admin has the given permission.
    ///
    /// Super admins always return true (short-circuit). Standard admins
    /// require a matching entry in the `permissions` JSONB object.
    pub fn can(&self, resource: &str, action: &str) -> bool {
        if self.level == AdminLevel::Super {
            return true;
        }
        self.permissions
            .get(resource)
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().any(|a| a.as_str() == Some(action)))
            .unwrap_or(false)
    }
}

impl FromRequest for AdminSession {
    type Error = AppError;
    type Future =
        std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, AppError>> + Send>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        let app_state = req.app_data::<web::Data<AppState>>().cloned();
        let header_value = req
            .headers()
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        Box::pin(async move {
            let state = app_state
                .ok_or_else(|| AppError::Internal(anyhow!("AppState missing from request")))?;

            let header_str = header_value.ok_or_else(|| {
                AppError::Unauthorized("missing authorization header".to_string())
            })?;

            if !header_str.starts_with("Bearer ") {
                return Err(AppError::Unauthorized(
                    "malformed authorization header".to_string(),
                ));
            }

            let token = &header_str[7..];
            if token.is_empty() {
                return Err(AppError::Unauthorized("empty bearer token".to_string()));
            }

            let claims = admin_jwt::verify_admin_access_token(&state.jwt_keys, token)?;

            // Re-read from DB — never trust JWT level/is_active claims for
            // authorization.
            let admin = sqlx::query!(
                r#"SELECT id, email, display_name, level, permissions, is_active
                   FROM admins WHERE id = $1"#,
                claims.sub,
            )
            .fetch_optional(&state.db)
            .await
            .map_err(AppError::from)?
            .ok_or_else(|| AppError::Unauthorized("admin not found".into()))?;

            if !admin.is_active {
                return Err(AppError::Unauthorized("admin account is inactive".into()));
            }

            Ok(AdminSession {
                id: admin.id,
                email: admin.email,
                display_name: admin.display_name,
                level: AdminLevel::from(admin.level),
                permissions: admin.permissions,
                is_active: admin.is_active,
            })
        })
    }
}

// ---------------------------------------------------------------------------
// SuperAdminSession extractor — wraps AdminSession, requires level == "super"
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct SuperAdminSession(pub AdminSession);

impl FromRequest for SuperAdminSession {
    type Error = AppError;
    type Future =
        std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, AppError>> + Send>>;

    fn from_request(req: &HttpRequest, payload: &mut Payload) -> Self::Future {
        let admin_fut = AdminSession::from_request(req, payload);
        Box::pin(async move {
            let admin = admin_fut.await?;
            if admin.level != AdminLevel::Super {
                return Err(AppError::Forbidden);
            }
            Ok(SuperAdminSession(admin))
        })
    }
}
