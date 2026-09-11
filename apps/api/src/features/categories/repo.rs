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

    /// Create a new category.
    ///
    /// Fails with `AppError::Conflict` if the slug already exists (unique
    /// constraint on `categories.slug`).
    pub async fn create_category(
        &self,
        slug: &str,
        label: &str,
        sort_order: i16,
    ) -> Result<CategoryResponse, AppError> {
        let category = sqlx::query_as!(
            CategoryResponse,
            r#"INSERT INTO categories (slug, label, sort_order)
               VALUES ($1, $2, $3)
               RETURNING id, slug, label"#,
            slug,
            label,
            sort_order,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(category)
    }

    /// Update a category's slug/label/sort_order. Only provided (non-None)
    /// fields are updated.
    ///
    /// Fails with `AppError::NotFound` if the category doesn't exist, or
    /// `AppError::Conflict` if the new slug collides with another category.
    pub async fn update_category(
        &self,
        id: i16,
        slug: Option<&str>,
        label: Option<&str>,
        sort_order: Option<i16>,
    ) -> Result<CategoryResponse, AppError> {
        let category = sqlx::query_as!(
            CategoryResponse,
            r#"UPDATE categories
               SET slug = COALESCE($2, slug),
                   label = COALESCE($3, label),
                   sort_order = COALESCE($4, sort_order)
               WHERE id = $1
               RETURNING id, slug, label"#,
            id,
            slug,
            label,
            sort_order,
        )
        .fetch_optional(&self.db)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("category with id {id} not found")))?;
        Ok(category)
    }

    /// Count listings referencing a category.
    pub async fn count_listings(&self, id: i16) -> Result<i64, AppError> {
        let count = sqlx::query_scalar!(
            r#"SELECT COUNT(*) as "count!" FROM listings WHERE category_id = $1"#,
            id,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(count)
    }

    /// Delete a category by ID.
    ///
    /// Fails with `AppError::NotFound` if the category doesn't exist, or
    /// `AppError::Conflict` if any listings reference it — the schema's
    /// `ON DELETE CASCADE` would silently destroy user data, so deletion is
    /// refused at the application layer and the admin must reassign or
    /// delete the listings first.
    pub async fn delete_category(&self, id: i16) -> Result<(), AppError> {
        let result = sqlx::query!("DELETE FROM categories WHERE id = $1", id)
            .execute(&self.db)
            .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound(format!(
                "category with id {id} not found"
            )));
        }
        Ok(())
    }
}
