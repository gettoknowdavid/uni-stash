use crate::core::error::AppError;

#[derive(Clone, Debug)]
pub struct AdminManagementRepo {
    db: sqlx::PgPool,
}

impl AdminManagementRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    pub async fn begin(&self) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AppError> {
        Ok(self.db.begin().await?)
    }

    /// Count active super admins.
    pub async fn count_active_supers(&self) -> Result<i64, AppError> {
        let row = sqlx::query_scalar!(
            "SELECT COUNT(*) as \"count!\" FROM admins WHERE level = 'super' AND is_active = true"
        )
        .fetch_one(&self.db)
        .await?;
        Ok(row)
    }

    /// Count active super admins excluding a specific admin.
    pub async fn count_active_supers_excluding(
        &self,
        exclude_id: uuid::Uuid,
    ) -> Result<i64, AppError> {
        let row = sqlx::query_scalar!(
            "SELECT COUNT(*) as \"count!\" FROM admins
             WHERE level = 'super' AND is_active = true AND id != $1",
            exclude_id,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(row)
    }

    /// Create a new admin within a transaction. Returns the created admin row.
    pub async fn create_admin(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        input: &CreateAdminInput<'_>,
    ) -> Result<AdminRow, AppError> {
        let admin = sqlx::query_as!(
            AdminRow,
            r#"INSERT INTO admins (email, password_hash, display_name, level, permissions, created_by)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, email, display_name, level, is_active, created_at"#,
            input.email,
            input.password_hash,
            input.display_name,
            input.level,
            input.permissions,
            input.created_by,
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(admin)
    }

    /// List all admins.
    pub async fn list_admins(&self) -> Result<Vec<AdminRow>, AppError> {
        let admins = sqlx::query_as!(
            AdminRow,
            "SELECT id, email, display_name, level, is_active, created_at
             FROM admins ORDER BY created_at DESC"
        )
        .fetch_all(&self.db)
        .await?;
        Ok(admins)
    }

    /// Partial update of an admin within a transaction.
    pub async fn update_admin(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        admin_id: uuid::Uuid,
        display_name: Option<&str>,
        level: Option<&str>,
        permissions: Option<&serde_json::Value>,
        is_active: Option<bool>,
    ) -> Result<AdminRow, AppError> {
        let admin = sqlx::query_as!(
            AdminRow,
            r#"UPDATE admins
               SET display_name = COALESCE($2, display_name),
                   level = COALESCE($3, level),
                   permissions = COALESCE($4, permissions),
                   is_active = COALESCE($5, is_active),
                   updated_at = now()
               WHERE id = $1
               RETURNING id, email, display_name, level, is_active, created_at"#,
            admin_id,
            display_name,
            level,
            permissions,
            is_active,
        )
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("admin with id {admin_id} not found")))?;
        Ok(admin)
    }

    /// Soft-delete (set is_active = false) within a transaction.
    pub async fn deactivate_admin(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        admin_id: uuid::Uuid,
    ) -> Result<AdminRow, AppError> {
        let admin = sqlx::query_as!(
            AdminRow,
            "UPDATE admins SET is_active = false, updated_at = now()
             WHERE id = $1
             RETURNING id, email, display_name, level, is_active, created_at",
            admin_id,
        )
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("admin with id {admin_id} not found")))?;
        Ok(admin)
    }

    /// Insert an audit log entry within a transaction.
    pub async fn insert_audit_log(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        admin_id: uuid::Uuid,
        action: &str,
        target_type: Option<&str>,
        target_id: Option<&str>,
        metadata: &serde_json::Value,
    ) -> Result<(), AppError> {
        sqlx::query!(
            "INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, metadata)
             VALUES ($1, $2, $3, $4, $5)",
            admin_id,
            action,
            target_type,
            target_id,
            metadata,
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

pub struct CreateAdminInput<'a> {
    pub email: &'a str,
    pub password_hash: &'a str,
    pub display_name: &'a str,
    pub level: &'a str,
    pub permissions: &'a serde_json::Value,
    pub created_by: uuid::Uuid,
}

/// Minimal admin row for list/create/update responses (no password_hash).
pub struct AdminRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: String,
    pub level: String,
    pub is_active: bool,
    pub created_at: time::OffsetDateTime,
}
