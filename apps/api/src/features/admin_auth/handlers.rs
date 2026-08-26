use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::core::auth::middleware::AdminSession;
use crate::core::auth::{self, admin_jwt, otp};
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::admin_auth::dtos::{
    AdminForgotPasswordRequest, AdminLoginRequest, AdminLoginResponse, AdminLogoutRequest,
    AdminRefreshRequest, AdminRefreshResponse, AdminResetPasswordRequest,
};

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

pub async fn login(
    state: web::Data<AppState>,
    body: ValidatedJson<AdminLoginRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    state.email_limiter.check_and_record(&body.email)?;
    let admin_opt = state
        .admin_auth_repo
        .find_admin_by_email(&body.email)
        .await?;
    let (hash, admin) = match &admin_opt {
        Some(a) => (a.password_hash.clone(), Some(a)),
        None => (auth::password::dummy_hash().to_string(), None),
    };
    let password_ok = auth::password::verify_password(&body.password, &hash)?;
    let admin = match (admin, password_ok) {
        (Some(a), true) => a,
        _ => return Err(AppError::Unauthorized("invalid credentials".into())),
    };
    if !admin.is_active {
        // Same generic error as wrong password — no enumeration of deactivated accounts
        return Err(AppError::Unauthorized("invalid credentials".into()));
    }
    let access_token = admin_jwt::sign_admin_access_token(&state.jwt_keys, admin.id, &admin.level)?;
    let family_id = uuid::Uuid::new_v4();
    let (refresh_token, _id) = state
        .admin_auth_repo
        .issue_admin_refresh_token(&state.db, admin.id, family_id)
        .await?;
    Ok(HttpResponse::Ok().json(ApiResponse::<AdminLoginResponse, ErrorBody>::success(
        AdminLoginResponse {
            access_token,
            refresh_token,
            expires_in: 900,
        },
        "login successful",
    )))
}

// ---------------------------------------------------------------------------
// Refresh
// ---------------------------------------------------------------------------

pub async fn refresh(
    state: web::Data<AppState>,
    body: ValidatedJson<AdminRefreshRequest>,
) -> Result<HttpResponse, AppError> {
    let now = time::OffsetDateTime::now_utc();

    let hash = auth::refresh_token::hash_refresh_token(&body.refresh_token);
    let row = state
        .admin_auth_repo
        .find_admin_refresh_token_by_hash(&hash)
        .await?
        .ok_or_else(|| AppError::Unauthorized("invalid refresh token".into()))?;

    if row.expires_at < now {
        return Err(AppError::Unauthorized("refresh token expired".into()));
    }

    if row.revoked {
        let (access, refresh, expires) = state
            .admin_auth_repo
            .handle_reused_admin_token(&state.jwt_keys, &row)
            .await?;
        return Ok(HttpResponse::Ok().json(ApiResponse::<AdminRefreshResponse, ErrorBody>::success(
            AdminRefreshResponse {
                access_token: access,
                refresh_token: refresh,
                expires_in: expires,
            },
            "token refreshed",
        )));
    }

    let (access, refresh, expires) = state
        .admin_auth_repo
        .rotate_admin_from_row(&state.jwt_keys, &row)
        .await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<AdminRefreshResponse, ErrorBody>::success(
        AdminRefreshResponse {
            access_token: access,
            refresh_token: refresh,
            expires_in: expires,
        },
        "token refreshed",
    )))
}

// ---------------------------------------------------------------------------
// Logout — idempotent
// ---------------------------------------------------------------------------

pub async fn logout(
    state: web::Data<AppState>,
    body: ValidatedJson<AdminLogoutRequest>,
) -> Result<HttpResponse, AppError> {
    state
        .admin_auth_repo
        .revoke_admin_refresh_token_by_hash(&body.refresh_token)
        .await?;
    Ok(HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
        (),
        "logged out successfully",
    )))
}

// ---------------------------------------------------------------------------
// Me — returns DB-fresh profile
// ---------------------------------------------------------------------------

pub async fn me(
    state: web::Data<AppState>,
    session: AdminSession,
) -> Result<HttpResponse, AppError> {
    let profile = state
        .admin_auth_repo
        .find_admin_profile_by_id(&session.id)
        .await?
        .ok_or_else(|| AppError::NotFound("admin not found".into()))?;
    Ok(HttpResponse::Ok().json(ApiResponse::success(profile, "ok")))
}

// ---------------------------------------------------------------------------
// Forgot password — always returns 200 (enumeration protection)
// ---------------------------------------------------------------------------

pub async fn forgot_password(
    state: web::Data<AppState>,
    body: ValidatedJson<AdminForgotPasswordRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    state.email_limiter.check_and_record(&body.email)?;

    let admin_opt = state
        .admin_auth_repo
        .find_admin_by_email(&body.email)
        .await?;

    if let Some(admin) = admin_opt {
        let (otp_code, _otp_id) = state.admin_auth_repo.insert_admin_otp(admin.id).await?;

        if let Err(e) = state
            .smtp
            .send_otp_email(&admin.email, &otp_code, "admin_password_reset")
            .await
        {
            tracing::warn!(
                error = %e,
                email = %admin.email,
                "failed to send admin password reset OTP"
            );
        }
    }

    // Always return success — don't reveal whether the email exists
    Ok(HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
        (),
        "if an account with that email exists, a reset code has been sent",
    )))
}

// ---------------------------------------------------------------------------
// Reset password — also revokes all active admin sessions
// ---------------------------------------------------------------------------

pub async fn reset_password(
    state: web::Data<AppState>,
    body: ValidatedJson<AdminResetPasswordRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    otp::validate_otp_format(&body.code)?;

    let admin_id = state.admin_auth_repo.verify_admin_otp(&body.code).await?;

    let new_hash = auth::password::hash_password(&body.new_password)?;
    state
        .admin_auth_repo
        .update_admin_password_hash(&admin_id, &new_hash)
        .await?;

    // Revoke ALL active refresh tokens for this admin — stricter than the
    // student flow, which doesn't currently do this. An admin account reset
    // should not leave stale sessions sitting around if the reset was
    // triggered because the password was compromised. The higher blast
    // radius per admin account (one admin can access schools, listings
    // moderation, user management, etc.) justifies the stricter policy.
    state
        .admin_auth_repo
        .revoke_all_admin_tokens(admin_id)
        .await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
        (),
        "password updated successfully",
    )))
}
