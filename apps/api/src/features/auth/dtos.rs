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

// ---------------------------------------------------------------------------
// OTP verification (replaces VerifyEmailRequest)
// ---------------------------------------------------------------------------

#[derive(Debug, serde::Deserialize, validator::Validate)]
pub struct VerifyOtpRequest {
    /// 6-digit OTP code received via email.
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    /// The OTP type: "email_verify" or "password_reset".
    pub otp_type: String,
}

#[derive(serde::Serialize)]
pub struct VerifyOtpResponse {
    pub verified: bool,
    /// Tokens are only included for email_verify (user just signed up).
    /// For password_reset, the user must login with their new password.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_in: Option<i64>,
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

// ---------------------------------------------------------------------------
// Resend verification
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResendVerificationRequest {
    #[validate(email)]
    pub email: String,
}

// ---------------------------------------------------------------------------
// Forgot password
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ForgotPasswordRequest {
    #[validate(email)]
    pub email: String,
}

// ---------------------------------------------------------------------------
// Reset password
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResetPasswordRequest {
    /// The OTP code received via the password reset email.
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    /// The new password (min 10 characters).
    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub new_password: String,
}
