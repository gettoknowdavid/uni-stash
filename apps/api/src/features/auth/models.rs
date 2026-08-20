#[derive(sqlx::FromRow)]
pub struct School {
    pub id: i16,
    pub name: String,
    pub domain: String,
    pub created_at: time::OffsetDateTime,
}

#[derive(sqlx::FromRow)]
pub struct User {
    pub id: uuid::Uuid,
    pub school_id: i16,
    pub email: String,
    pub password_hash: String,
    pub display_name: String,
    pub email_verified: bool,
    pub role: String,
    pub created_at: time::OffsetDateTime,
    pub updated_at: time::OffsetDateTime,
}

#[derive(sqlx::FromRow)]
pub struct RefreshToken {
    pub id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub token_hash: String,
    pub family_id: uuid::Uuid,
    pub revoked: bool,
    pub revoked_at: Option<time::OffsetDateTime>,
    pub superseded_by: Option<uuid::Uuid>,
    pub expires_at: time::OffsetDateTime,
    pub created_at: time::OffsetDateTime,
}
