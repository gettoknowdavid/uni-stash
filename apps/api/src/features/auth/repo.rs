use crate::{
    core::error::AppError,
    features::auth::{
        dtos::InsertUserInput,
        models::{School, User},
    },
};

#[derive(Clone, Debug)]
pub struct AuthRepo {
    db: sqlx::PgPool,
}

impl AuthRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    pub async fn find_school_by_domain(&self, email: &str) -> Result<Option<School>, AppError> {
        if !email.contains("@") {
            return Err(AppError::BadRequest("invalid email".to_string()));
        }
        let domain = email.split("@").last().unwrap_or("");
        let school = sqlx::query_as!(School, "SELECT * FROM schools WHERE domain = $1", domain)
            .fetch_optional(&self.db)
            .await?;
        Ok(school)
    }

    pub async fn insert_user<'a>(&self, input: &InsertUserInput<'a>) -> Result<User, AppError> {
        let user = sqlx::query_as!(
            User,
            r#"INSERT INTO users (school_id, email, password_hash, display_name)
            VALUES ($1, $2, $3, $4)
            RETURNING *"#,
            input.school_id,
            input.email,
            input.password,
            input.display_name,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(user)
    }
}
