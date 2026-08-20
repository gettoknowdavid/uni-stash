use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::core::auth;
use crate::core::error::AppError;
use crate::core::state::AppState;
use crate::features::auth::dtos::{InsertUserInput, SignUpRequest, SignUpResponse};

pub async fn signup(
    state: web::Data<AppState>,
    body: web::Json<SignUpRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
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
