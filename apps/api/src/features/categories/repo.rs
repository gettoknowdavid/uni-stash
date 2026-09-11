use crate::core::error::AppError;
use crate::features::categories::dtos::CategoryResponse;

#[derive(Clone, Debug)]
pub struct CategoriesRepo {
    db: sqlx::PgPool,
}

impl CategoriesRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// List all categories ordered by `sort_order`, then label as a stable
    /// tiebreaker
    pub async fn list_categories(&self) -> Result<Vec<CategoryResponse>, AppError> {
        let categories = sqlx::query_as!(
            CategoryResponse,
            r#"SELECT id, slug, label
               FROM categories
               ORDER BY sort_order ASC, label ASC"#,
        )
        .fetch_all(&self.db)
        .await?;
        Ok(categories)
    }
}
