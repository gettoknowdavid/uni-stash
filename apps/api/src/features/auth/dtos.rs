/// Generic wrapper for auth responses that include tokens + user.
///
/// Serializes as:
/// ```json
/// {
///   "access_token": "...",
///   "refresh_token": "...",
///   "expires_in": 900,
///   "user": { ... }
/// }
/// ```
#[derive(serde::Serialize)]
pub struct AuthData<T: serde::Serialize> {
    #[serde(flatten)]
    pub tokens: T,
    pub user: UserProfile,
}

// ---------------------------------------------------------------------------
// Token-only response types (flattened inside AuthData)
// ---------------------------------------------------------------------------

#[derive(serde::Serialize)]
pub struct SignUpTokens {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_in: Option<i64>,
}

#[derive(serde::Serialize)]
pub struct LoginTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Serialize)]
pub struct RefreshTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(serde::Serialize)]
pub struct VerifyOtpTokens {
    pub verified: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_in: Option<i64>,
}

// ---------------------------------------------------------------------------
// User profile (embedded in auth responses)
// ---------------------------------------------------------------------------

/// Slim user profile returned inside auth responses and GET /auth/me.
#[derive(serde::Serialize, sqlx::FromRow, Clone)]
pub struct UserProfile {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub email_verified: bool,
    pub role: String,
}

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct SignUpRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub password: String,

    #[validate(length(min = 1, max = 80))]
    pub display_name: String,
}

pub struct InsertUserInput<'a> {
    pub school_id: i16,
    pub email: &'a str,
    pub password: &'a str,
    pub display_name: &'a str,
}

// -------------------------------------------------------------------
// OTP verification (replaces VerifyEmailRequest)
// -------------------------------------------------------------------

#[derive(Debug, serde::Deserialize, validator::Validate)]
pub struct VerifyOtpRequest {
    /// 6-digit OTP code received via email.
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    /// The OTP type: "email_verify" or "password_reset".
    pub otp_type: String,
}

#[derive(serde::Deserialize, validator::Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(serde::Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(serde::Deserialize)]
pub struct LogoutRequest {
    pub refresh_token: String,
}

// -------------------------------------------------------------------
// Resend verification
// -------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResendVerificationRequest {
    #[validate(email)]
    pub email: String,
}

// -------------------------------------------------------------------
// Forgot password
// -------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ForgotPasswordRequest {
    #[validate(email)]
    pub email: String,
}

// -------------------------------------------------------------------
// Reset password
// -------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResetPasswordRequest {
    /// The OTP code received via the password reset email.
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    /// The new password (min 10 characters).
    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub new_password: String,
}
