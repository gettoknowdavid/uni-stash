#[derive(Clone, Debug, sqlx::FromRow)]
pub struct School {
    pub id: i16,
    pub name: String,
    pub domain: String,
    pub created_at: time::OffsetDateTime,
}

#[derive(Clone, Debug, sqlx::FromRow)]
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
