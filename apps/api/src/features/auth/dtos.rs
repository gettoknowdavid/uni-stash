#[derive(serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct SignUpRequest {
    #[validate(email)]
    #[schema(value_type = String, format = Email, example = "alice@university.edu")]
    pub email: String,

    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    #[schema(value_type = String, min_length = 10, example = "correct horse battery staple")]
    pub password: String,

    #[validate(length(min = 1, max = 80))]
    #[schema(value_type = String, min_length = 1, max_length = 80, example = "Alice")]
    pub display_name: String,
}

#[derive(serde::Serialize, utoipa::ToSchema)]
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

#[derive(serde::Deserialize, utoipa::ToSchema)]
pub struct VerifyEmailRequest {
    #[schema(value_type = String, example = "eyJhbGciOiJSUzI1NiJ9...")]
    pub token: String,
}

#[derive(serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct LoginRequest {
    #[validate(email)]
    #[schema(value_type = String, format = Email, example = "alice@university.edu")]
    pub email: String,

    #[validate(length(min = 1))]
    #[schema(value_type = String, min_length = 1, example = "correct horse battery staple")]
    pub password: String,
}

#[derive(serde::Serialize, utoipa::ToSchema)]
pub struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Deserialize, utoipa::ToSchema)]
pub struct RefreshRequest {
    #[schema(value_type = String, example = "abc123...")]
    pub refresh_token: String,
}

#[derive(serde::Serialize, utoipa::ToSchema)]
pub struct RefreshResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Deserialize, utoipa::ToSchema)]
pub struct LogoutRequest {
    #[schema(value_type = String, example = "abc123...")]
    pub refresh_token: String,
}
