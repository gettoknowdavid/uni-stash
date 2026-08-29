use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::core::auth::middleware::AuthUser;
use crate::core::auth::{self, jwt, otp, password};
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::auth::dtos::{
    AuthData, ForgotPasswordRequest, InsertUserInput, LoginRequest, LoginTokens, LogoutRequest,
    RefreshRequest, RefreshTokens, ResetPasswordRequest, SignUpRequest, SignUpTokens,
    VerifyOtpRequest, VerifyOtpTokens,
};
use crate::features::auth::repo::AuthRepo;

// ---------------------------------------------------------------------------
// Signup (CM-3.4) — now sends OTP instead of JWT token
// ---------------------------------------------------------------------------

pub async fn signup(
    state: web::Data<AppState>,
    body: ValidatedJson<SignUpRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    state.email_limiter.check_and_record(&body.email)?;
    let school = state
        .auth_repo
        .find_school_by_domain(&body.email)
        .await?
        .ok_or(AppError::BadRequest(
            "email domain not recognized as partner school".to_string(),
        ))?;
    let password_hash = auth::password::hash_password(&body.password)?;
    let user = state
        .auth_repo
        .insert_user(&InsertUserInput {
            school_id: school.id,
            email: &body.email,
            password: &password_hash,
            display_name: &body.display_name,
        })
        .await?;

    // Issue tokens so the client can store them and reach the
    // OTP-verification flow on relaunch.
    let access_token = jwt::sign_access_token(&state.jwt_keys, &user)?;
    let family_id = uuid::Uuid::new_v4();
    let (refresh_token, _id) = state
        .auth_repo
        .issue_refresh_token(&state.db, user.id, family_id)
        .await?;

    // Generate OTP and send via email.
    let (otp_code, _otp_id) = state.auth_repo.insert_otp(user.id, "email_verify").await?;

    // Best-effort email — if SMTP fails, the user row exists and they
    // can use POST /auth/resend-verification to retry.
    if let Err(e) = state
        .smtp
        .send_otp_email(&user.email, &otp_code, "email_verify")
        .await
    {
        tracing::warn!(error = %e, email = %user.email, "failed to send verification OTP");
    }

    let profile = AuthRepo::user_to_profile(&user);

    Ok(
        HttpResponse::Created().json(ApiResponse::<AuthData<SignUpTokens>, ErrorBody>::success(
            AuthData {
                tokens: SignUpTokens {
                    access_token: Some(access_token),
                    refresh_token: Some(refresh_token),
                    expires_in: Some(900),
                },
                user: profile,
            },
            "account created successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// Verify OTP (replaces verify_email) — CM-3.5
// ---------------------------------------------------------------------------

/// Verify an OTP code. Works for both email verification and password reset.
///
/// The client passes `type` to indicate which flow it's completing.
pub async fn verify_otp(
    state: web::Data<AppState>,
    body: ValidatedJson<VerifyOtpRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    otp::validate_otp_format(&body.code)?;

    let user_id = state
        .auth_repo
        .verify_otp(&body.code, &body.otp_type)
        .await?;

    // If this was an email verification OTP, mark the user as verified
    // and issue tokens so the user can start using the app immediately
    // without a redundant login.
    if body.otp_type == "email_verify" {
        state.auth_repo.mark_email_verified(&user_id).await?;

        let user = state
            .auth_repo
            .find_user_by_id(&user_id)
            .await?
            .ok_or(AppError::NotFound("user not found".into()))?;

        let access_token = jwt::sign_access_token(&state.jwt_keys, &user)?;
        let family_id = uuid::Uuid::new_v4();
        let (refresh_token, _id) = state
            .auth_repo
            .issue_refresh_token(&state.db, user.id, family_id)
            .await?;

        let profile = AuthRepo::user_to_profile(&user);

        return Ok(HttpResponse::Ok().json(
            ApiResponse::<AuthData<VerifyOtpTokens>, ErrorBody>::success(
                AuthData {
                    tokens: VerifyOtpTokens {
                        verified: true,
                        access_token: Some(access_token),
                        refresh_token: Some(refresh_token),
                        expires_in: Some(900),
                    },
                    user: profile,
                },
                "email verified successfully",
            ),
        ));
    }

    // password_reset — just confirm verification, no tokens (user must login
    // with their new password via the separate reset-password endpoint).
    Ok(
        HttpResponse::Ok().json(ApiResponse::<VerifyOtpTokens, ErrorBody>::success(
            VerifyOtpTokens {
                verified: true,
                access_token: None,
                refresh_token: None,
                expires_in: None,
            },
            "password reset verified",
        )),
    )
}

// ---------------------------------------------------------------------------
// Resend verification — new endpoint
// ---------------------------------------------------------------------------

/// Resend an OTP for email verification.
///
/// Generates a fresh OTP and sends it. The previous OTP is automatically
/// invalidated. Idempotent from the user's perspective — they just get
/// a new code.
pub async fn resend_verification(
    state: web::Data<AppState>,
    body: ValidatedJson<crate::features::auth::dtos::ResendVerificationRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let user = state
        .auth_repo
        .find_user_by_email(&body.email)
        .await?
        .ok_or(AppError::NotFound("no account with this email".into()))?;

    if user.email_verified {
        return Err(AppError::BadRequest("email is already verified".into()));
    }

    let (otp_code, _otp_id) = state.auth_repo.insert_otp(user.id, "email_verify").await?;

    if let Err(e) = state
        .smtp
        .send_otp_email(&user.email, &otp_code, "email_verify")
        .await
    {
        tracing::warn!(error = %e, email = %user.email, "failed to resend verification OTP");
        return Err(AppError::Internal(anyhow::anyhow!(
            "failed to send verification email"
        )));
    }

    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "verification code sent",
        )),
    )
}

// ---------------------------------------------------------------------------
// Forgot password — new endpoint
// ---------------------------------------------------------------------------

/// Request a password reset OTP.
///
/// Always returns 200 regardless of whether the email exists — prevents
/// user enumeration. The OTP is only sent if the email matches a real account.
pub async fn forgot_password(
    state: web::Data<AppState>,
    body: ValidatedJson<ForgotPasswordRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    // Always return 200 to prevent user enumeration
    let user_opt = state.auth_repo.find_user_by_email(&body.email).await?;

    if let Some(user) = user_opt {
        let (otp_code, _otp_id) = state
            .auth_repo
            .insert_otp(user.id, "password_reset")
            .await?;

        if let Err(e) = state
            .smtp
            .send_otp_email(&user.email, &otp_code, "password_reset")
            .await
        {
            tracing::warn!(error = %e, email = %user.email, "failed to send password reset OTP");
        }
    }

    // Always return success — don't reveal whether the email exists
    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "if an account with that email exists, a reset code has been sent",
        )),
    )
}

// ---------------------------------------------------------------------------
// Reset password — new endpoint
// ---------------------------------------------------------------------------

/// Reset password using a valid OTP code.
///
/// Verifies the OTP (must be type `password_reset`), then updates the
/// user's password. The OTP is consumed (single-use).
pub async fn reset_password(
    state: web::Data<AppState>,
    body: ValidatedJson<ResetPasswordRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    otp::validate_otp_format(&body.code)?;

    let user_id = state
        .auth_repo
        .verify_otp(&body.code, "password_reset")
        .await?;

    let new_hash = auth::password::hash_password(&body.new_password)?;
    state
        .auth_repo
        .update_password_hash(&user_id, &new_hash)
        .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "password updated successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// Login (CM-3.6) — returns tokens + user
// ---------------------------------------------------------------------------

pub async fn login(
    state: web::Data<AppState>,
    body: ValidatedJson<LoginRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    state.email_limiter.check_and_record(&body.email)?;
    let user_opt = state.auth_repo.find_user_by_email(&body.email).await?;
    let (hash, user) = match &user_opt {
        Some(u) => (u.password_hash.clone(), Some(u)),
        None => (password::dummy_hash().to_string(), None),
    };
    let password_ok = password::verify_password(&body.password, &hash)?;
    let user = match (user, password_ok) {
        (Some(u), true) => u,
        _ => return Err(AppError::Unauthorized("invalid credentials".into())),
    };
    if !user.email_verified {
        return Err(AppError::EmailNotVerified);
    }
    let access_token = jwt::sign_access_token(&state.jwt_keys, user)?;
    let family_id = uuid::Uuid::new_v4();
    let (refresh_token, _id) = state
        .auth_repo
        .issue_refresh_token(&state.db, user.id, family_id)
        .await?;

    let profile = AuthRepo::user_to_profile(user);

    Ok(
        HttpResponse::Ok().json(ApiResponse::<AuthData<LoginTokens>, ErrorBody>::success(
            AuthData {
                tokens: LoginTokens {
                    access_token,
                    refresh_token,
                    expires_in: 900,
                },
                user: profile,
            },
            "login successful",
        )),
    )
}

// ---------------------------------------------------------------------------
// Refresh (CM-3.7 / CM-3.8) — returns tokens + user
// ---------------------------------------------------------------------------

pub async fn refresh(
    state: web::Data<AppState>,
    body: ValidatedJson<RefreshRequest>,
) -> Result<HttpResponse, AppError> {
    let now = time::OffsetDateTime::now_utc();

    let hash = auth::refresh_token::hash_refresh_token(&body.refresh_token);
    let row = state
        .auth_repo
        .find_refresh_token_by_hash(&hash)
        .await?
        .ok_or_else(|| AppError::Unauthorized("invalid refresh token".into()))?;

    if row.expires_at < now {
        return Err(AppError::Unauthorized("refresh token expired".into()));
    }

    if row.revoked {
        let (access, refresh, expires, profile) = state
            .auth_repo
            .handle_reused_token(&state.jwt_keys, &row)
            .await?;
        return Ok(HttpResponse::Ok().json(
            ApiResponse::<AuthData<RefreshTokens>, ErrorBody>::success(
                AuthData {
                    tokens: RefreshTokens {
                        access_token: access,
                        refresh_token: refresh,
                        expires_in: expires,
                    },
                    user: profile,
                },
                "token refreshed",
            ),
        ));
    }

    let (access, refresh, expires, profile) = state
        .auth_repo
        .rotate_from_row(&state.jwt_keys, &row)
        .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<AuthData<RefreshTokens>, ErrorBody>::success(
            AuthData {
                tokens: RefreshTokens {
                    access_token: access,
                    refresh_token: refresh,
                    expires_in: expires,
                },
                user: profile,
            },
            "token refreshed",
        )),
    )
}

// ---------------------------------------------------------------------------
// Logout (CM-3.9) — unchanged
// ---------------------------------------------------------------------------

pub async fn logout(
    state: web::Data<AppState>,
    body: ValidatedJson<LogoutRequest>,
) -> Result<HttpResponse, AppError> {
    state
        .auth_repo
        .revoke_refresh_token_by_hash(&body.refresh_token)
        .await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "logged out successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// Me (CM-3.9) — unchanged
// ---------------------------------------------------------------------------

pub async fn me(state: web::Data<AppState>, user: AuthUser) -> Result<HttpResponse, AppError> {
    let profile = state
        .auth_repo
        .find_user_profile_by_id(&user.id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    Ok(HttpResponse::Ok().json(ApiResponse::success(profile, "ok")))
}
