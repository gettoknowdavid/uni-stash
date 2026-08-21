use actix_web::{HttpResponse, web};
use serde_json::json;
use validator::Validate;

use crate::core::auth::middleware::AuthUser;
use crate::core::auth::{self, jwt, password};
use crate::core::error::AppError;
use crate::core::state::AppState;
use crate::features::auth::dtos::{
    InsertUserInput, LoginRequest, LoginResponse, LogoutRequest, RefreshRequest, RefreshResponse,
    SignUpRequest, SignUpResponse, VerifyEmailRequest,
};

pub async fn signup(
    state: web::Data<AppState>,
    body: web::Json<SignUpRequest>,
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
    let verify_token = auth::jwt::sign_email_verify_token(&state.jwt_keys, &user)?;
    state
        .resend
        .send_verification_email(&user.email, &verify_token)
        .await?;
    Ok(HttpResponse::Created().json(SignUpResponse {
        id: user.id,
        email: user.email,
        display_name: user.display_name,
        email_verified: false,
    }))
}

// Single-use enforcement decision: this token is NOT tracked as single-use
// in the DB. The 30-minute expiry (jwt.rs EMAIL_VERIFY_TTL_MINUTES) is the
// only defense against replay. Rationale: unlike refresh tokens, a replayed
// verify-email token has a low-severity blast radius — it can only flip
// `email_verified` to true again (already-true is idempotent), not grant
// any new capability. Revisit if verify-email tokens ever carry more power.
pub async fn verify_email(
    state: web::Data<AppState>,
    body: web::Json<VerifyEmailRequest>,
) -> Result<HttpResponse, AppError> {
    let claims = jwt::verify_email_verify_token(&state.jwt_keys, &body.token)?;
    state.auth_repo.mark_email_verified(&claims.sub).await?;
    Ok(HttpResponse::Ok().json(json!({"email_verified": true})))
}

pub async fn login(
    state: web::Data<AppState>,
    body: web::Json<LoginRequest>,
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
    let access_token = jwt::sign_access_token(&state.jwt_keys, &user)?;
    let family_id = uuid::Uuid::new_v4();
    let (refresh_token, _id) = state
        .auth_repo
        .issue_refresh_token(&state.db, user.id, family_id)
        .await?;
    Ok(HttpResponse::Ok().json(LoginResponse {
        access_token,
        refresh_token,
        expires_in: 900,
    }))
}

/// POST /api/v1/auth/refresh
///
/// Rotate a refresh token: present the old one, get back a fresh access +
/// refresh pair. All three DB writes (revoke old, insert new, link
/// superseded_by) are atomic — a partial failure would strand the user
/// with no valid refresh token and no record of why.
///
/// This handler owns the business flow. The repo provides composable
/// primitives (find, revoke, issue, supersede); this function decides
/// the orchestration — expiry checks, reuse detection, transaction
/// boundaries, and JWT signing.
pub async fn refresh(
    state: web::Data<AppState>,
    body: web::Json<RefreshRequest>,
) -> Result<HttpResponse, AppError> {
    let now = time::OffsetDateTime::now_utc();

    // 1. Hash the presented token and look it up.
    let hash = auth::refresh_token::hash_refresh_token(&body.refresh_token);
    let row = state
        .auth_repo
        .find_refresh_token_by_hash(&hash)
        .await?
        .ok_or_else(|| AppError::Unauthorized("invalid refresh token".into()))?;

    // 2. Check expiry.
    if row.expires_at < now {
        return Err(AppError::Unauthorized("refresh token expired".into()));
    }

    // 3. Reuse detection — if already revoked, CM-3.8 decides the outcome:
    //    - Within grace window → legitimate duplicate, rotate from current token.
    //    - Outside grace → compromise, revoke entire family.
    if row.revoked {
        let (access, refresh, expires) = state
            .auth_repo
            .handle_reused_token(&state.jwt_keys, &row)
            .await?;
        return Ok(HttpResponse::Ok().json(RefreshResponse {
            access_token: access,
            refresh_token: refresh,
            expires_in: expires,
        }));
    }

    // 4. Happy path: single-use, not yet revoked — atomic rotation.
    let (access, refresh, expires) = state
        .auth_repo
        .rotate_from_row(&state.jwt_keys, &row)
        .await?;

    Ok(HttpResponse::Ok().json(RefreshResponse {
        access_token: access,
        refresh_token: refresh,
        expires_in: expires,
    }))
}

/// POST /api/v1/auth/logout
///
/// Revoke the presented refresh token.  Idempotent: always returns 200
/// regardless of whether the token was valid, already revoked, or unknown.
pub async fn logout(
    state: web::Data<AppState>,
    body: web::Json<LogoutRequest>,
) -> Result<HttpResponse, AppError> {
    state
        .auth_repo
        .revoke_refresh_token_by_hash(&body.refresh_token)
        .await?;
    Ok(HttpResponse::Ok().json(json!({ "status": "ok" })))
}

/// GET /api/v1/auth/me
///
/// Returns the authenticated user's profile.  `role` is fetched fresh from
/// the DB (not from JWT claims) — this avoids trusting a potentially stale
/// token for authorization-adjacent data, keeping role-trust discipline
/// consistent with CM-9.2's later pattern.
pub async fn me(state: web::Data<AppState>, user: AuthUser) -> Result<HttpResponse, AppError> {
    let profile = state
        .auth_repo
        .find_user_profile_by_id(&user.id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    Ok(HttpResponse::Ok().json(profile))
}
