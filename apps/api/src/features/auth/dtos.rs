#[derive(serde::Deserialize, validator::Validate)]
pub struct SignUpRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub password: String,

    #[validate(length(min = 1, max = 80))]
    pub display_name: String,
}

#[derive(serde::Serialize)]
pub struct SignUpResponse {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub email_verified: bool,
}

pub struct InsertUserInput<'a> {
    pub school_id: i16,
    pub email: &'a str,
    pub password: &'a str,
    pub display_name: &'a str,
}

#[derive(serde::Deserialize)]
pub struct VerifyEmailRequest {
    pub token: String,
}

#[derive(serde::Deserialize, validator::Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(serde::Serialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(serde::Serialize)]
pub struct RefreshResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Deserialize)]
pub struct LogoutRequest {
    pub refresh_token: String,
}
