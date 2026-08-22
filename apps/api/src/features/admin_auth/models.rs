#[derive(sqlx::FromRow)]
pub struct Admin {
    pub id: uuid::Uuid,
    pub email: String,
    pub password_hash: String,
    pub display_name: String,
    pub level: String,
    pub permissions: serde_json::Value,
    pub is_active: bool,
    pub created_by: Option<uuid::Uuid>,
    pub created_at: time::OffsetDateTime,
    pub updated_at: time::OffsetDateTime,
}

#[derive(sqlx::FromRow)]
pub struct AdminRefreshToken {
    pub id: uuid::Uuid,
    pub admin_id: uuid::Uuid,
    pub token_hash: String,
    pub family_id: uuid::Uuid,
    pub revoked: bool,
    pub revoked_at: Option<time::OffsetDateTime>,
    pub superseded_by: Option<uuid::Uuid>,
    pub expires_at: time::OffsetDateTime,
    pub created_at: time::OffsetDateTime,
}

/// Slim profile returned by GET /admin/auth/me.
///
/// Does NOT include `password_hash` or timestamps.
#[derive(serde::Serialize, sqlx::FromRow)]
pub struct AdminProfile {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub level: String,
    pub permissions: serde_json::Value,
    pub is_active: bool,
}

#[derive(sqlx::FromRow)]
pub struct AdminOtp {
    pub id: uuid::Uuid,
    pub admin_id: uuid::Uuid,
    pub code: String,
    pub r#type: String,
    pub expires_at: time::OffsetDateTime,
    pub used_at: Option<time::OffsetDateTime>,
    pub created_at: time::OffsetDateTime,
}
