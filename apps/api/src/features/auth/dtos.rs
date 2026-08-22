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

// ---------------------------------------------------------------------------
// OTP verification (replaces VerifyEmailRequest)
// ---------------------------------------------------------------------------

#[derive(Debug, serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct VerifyOtpRequest {
    /// 6-digit OTP code received via email.
    #[validate(length(min = 6, max = 6))]
    #[schema(value_type = String, example = "847291")]
    pub code: String,

    /// The OTP type: "email_verify" or "password_reset".
    #[schema(value_type = String, example = "email_verify")]
    pub otp_type: String,
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

// ---------------------------------------------------------------------------
// Resend verification
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct ResendVerificationRequest {
    #[validate(email)]
    #[schema(value_type = String, format = Email, example = "alice@university.edu")]
    pub email: String,
}

// ---------------------------------------------------------------------------
// Forgot password
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct ForgotPasswordRequest {
    #[validate(email)]
    #[schema(value_type = String, format = Email, example = "alice@university.edu")]
    pub email: String,
}

// ---------------------------------------------------------------------------
// Reset password
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate, utoipa::ToSchema)]
pub struct ResetPasswordRequest {
    /// The OTP code received via the password reset email.
    #[validate(length(min = 6, max = 6))]
    #[schema(value_type = String, example = "847291")]
    pub code: String,

    /// The new password (min 10 characters).
    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    #[schema(value_type = String, min_length = 10, example = "new secure password")]
    pub new_password: String,
}
