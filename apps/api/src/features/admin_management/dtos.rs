// ---------------------------------------------------------------------------
// Create admin
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct CreateAdminRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 10, message = "password must be at least 10 characters"))]
    pub password: String,

    #[validate(length(min = 1, max = 80))]
    pub display_name: String,

    /// "super" or "standard". Defaults to "standard" if omitted.
    pub level: Option<String>,

    /// Optional JSONB permissions object for standard admins.
    pub permissions: Option<serde_json::Value>,
}

#[derive(serde::Serialize)]
pub struct CreateAdminResponse {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub level: String,
    pub message: String,
}

// ---------------------------------------------------------------------------
// List admins — no additional DTO needed, returns AdminListItem array
// ---------------------------------------------------------------------------

#[derive(serde::Serialize)]
pub struct AdminListItem {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub level: String,
    pub is_active: bool,
    pub created_at: String,
}

#[derive(serde::Serialize)]
pub struct ListAdminsResponse {
    pub admins: Vec<AdminListItem>,
}

// ---------------------------------------------------------------------------
// Update admin
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize, validator::Validate)]
pub struct UpdateAdminRequest {
    #[validate(length(min = 1, max = 80))]
    pub display_name: Option<String>,

    /// "super" or "standard"
    pub level: Option<String>,

    /// JSONB permissions object for standard admins
    pub permissions: Option<serde_json::Value>,

    pub is_active: Option<bool>,
}

#[derive(serde::Serialize)]
pub struct UpdateAdminResponse {
    pub message: String,
}
