// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct AdminLoginRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(serde::Serialize)]
pub struct AdminLoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

// ---------------------------------------------------------------------------
// Refresh
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize)]
pub struct AdminRefreshRequest {
    pub refresh_token: String,
}

#[derive(serde::Serialize)]
pub struct AdminRefreshResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize)]
pub struct AdminLogoutRequest {
    pub refresh_token: String,
}

// ---------------------------------------------------------------------------
// Forgot password (email-only OTP)
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct AdminForgotPasswordRequest {
    #[validate(email)]
    pub email: String,
}

// ---------------------------------------------------------------------------
// Reset password
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct AdminResetPasswordRequest {
    #[validate(length(min = 6, max = 6))]
    pub code: String,

    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub new_password: String,
}
