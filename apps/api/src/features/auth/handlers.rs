use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::core::auth::middleware::AuthUser;
use crate::core::auth::{self, jwt, otp, password};
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::auth::dtos::{
    AuthData, DeleteAccountRequest, DeleteAccountResponse, ForgotPasswordRequest, InsertUserInput,
    LoginRequest, LoginTokens, LogoutRequest, ProfileStatsResponse, RefreshRequest, RefreshTokens,
    ResetPasswordRequest, SignUpRequest, SignUpTokens, UpdateProfileRequest, UserProfile,
    VerifyOtpRequest, VerifyOtpTokens,
};
use crate::features::auth::repo::AuthRepo;

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

pub async fn me(state: web::Data<AppState>, user: AuthUser) -> Result<HttpResponse, AppError> {
    let profile = state
        .auth_repo
        .find_user_profile_by_id(&user.id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    Ok(HttpResponse::Ok().json(ApiResponse::success(profile, "ok")))
}

/// Soft-delete the authenticated user's account.
///
/// The user must provide their current password for confirmation.
/// The account enters a 30-day grace period, after which it is
/// permanently hard-deleted by a background job.
pub async fn delete_account(
    state: web::Data<AppState>,
    auth_user: AuthUser,
    body: ValidatedJson<DeleteAccountRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    // Fetch the user (including already soft-deleted check)
    let user = state
        .auth_repo
        .find_user_by_id_including_deleted(&auth_user.id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;

    // Already soft-deleted?
    if user.deleted_at.is_some() {
        return Err(AppError::BadRequest(
            "account is already scheduled for deletion".into(),
        ));
    }

    // Verify password
    let password_ok = auth::password::verify_password(&body.password, &user.password_hash)?;
    if !password_ok {
        return Err(AppError::Unauthorized("invalid password".into()));
    }

    // Soft-delete the account
    state.auth_repo.soft_delete_user(&user.id).await?;

    // Revoke all refresh tokens (invalidate all sessions)
    state.auth_repo.revoke_all_user_tokens(&user.id).await?;

    // Fetch updated user to get the scheduled deletion timestamp
    let updated_user = state
        .auth_repo
        .find_user_by_id_including_deleted(&user.id)
        .await?
        .ok_or_else(|| {
            AppError::Internal(anyhow::anyhow!("user disappeared after soft-delete",))
        })?;

    let scheduled_at = updated_user
        .deletion_scheduled_at
        .map(|t| t.to_string())
        .unwrap_or_default();

    Ok(
        HttpResponse::Ok().json(ApiResponse::<DeleteAccountResponse, ErrorBody>::success(
            DeleteAccountResponse {
                message:
                    "account scheduled for deletion. It will be permanently deleted after 30 days."
                        .to_string(),
                deletion_scheduled_at: scheduled_at,
            },
            "account soft-deleted successfully",
        )),
    )
}

/// Update the authenticated user's profile.
///
/// Only `display_name` is updatable for now.  Future extensions: avatar,
/// bio, etc.
pub async fn update_profile(
    state: web::Data<AppState>,
    auth_user: AuthUser,
    body: ValidatedJson<UpdateProfileRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    if body.display_name.is_none() {
        return Err(AppError::BadRequest(
            "at least one field must be provided".to_string(),
        ));
    }

    state
        .auth_repo
        .update_user_profile(&auth_user.id, body.display_name.as_deref())
        .await?;

    // Re-read the profile to return the fresh state.
    let profile = state
        .auth_repo
        .find_user_profile_by_id(&auth_user.id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<UserProfile, ErrorBody>::success(
            profile,
            "profile updated successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// GET /api/v1/auth/me/stats — profile statistics
// ---------------------------------------------------------------------------

/// Get accurate listing counts for the authenticated user's profile.
///
/// Uses COUNT(*) queries — exact regardless of listing count.
pub async fn get_profile_stats(
    state: web::Data<AppState>,
    auth_user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let (active, sold) = state.auth_repo.get_user_stats(&auth_user.id).await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ProfileStatsResponse, ErrorBody>::success(
            ProfileStatsResponse {
                active_listings: active,
                items_sold: sold,
                saved: 0, // Not yet implemented
            },
            "ok",
        )),
    )
}
