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

/// Slim user profile returned inside auth responses and GET /auth/me.
#[derive(serde::Serialize, sqlx::FromRow, Clone)]
pub struct UserProfile {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub email_verified: bool,
    pub role: String,
}

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

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResendVerificationRequest {
    #[validate(email)]
    pub email: String,
}

#[derive(serde::Deserialize, validator::Validate)]
pub struct ForgotPasswordRequest {
    #[validate(email)]
    pub email: String,
}

#[derive(serde::Deserialize, validator::Validate)]
pub struct ResetPasswordRequest {
    /// The OTP code received via the password reset email.
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    /// The new password (min 10 characters).
    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub new_password: String,
}

/// Request body for soft-deleting the authenticated user's account.
///
/// The user must confirm with their password.  After soft-deletion,
/// the account enters a 30-day grace period during which it can be
/// recovered by contacting support.  After the grace period, the
/// account is permanently hard-deleted from the database.
#[derive(serde::Deserialize, validator::Validate)]
pub struct DeleteAccountRequest {
    /// Current password to confirm identity.
    #[validate(length(min = 1, message = "password is required"))]
    pub password: String,
}

#[derive(serde::Serialize)]
pub struct DeleteAccountResponse {
    pub message: String,
    pub deletion_scheduled_at: String,
}

/// Request body for updating the authenticated user's profile.
///
/// All fields are optional — only provided fields are updated.
#[derive(serde::Deserialize, validator::Validate)]
pub struct UpdateProfileRequest {
    /// New display name (if changing).
    #[validate(length(min = 1, max = 80, message = "display_name must be 1-80 characters"))]
    pub display_name: Option<String>,
}
