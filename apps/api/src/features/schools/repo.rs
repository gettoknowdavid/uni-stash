use crate::core::error::AppError;
use crate::features::auth::models::School;

#[derive(Clone, Debug)]
pub struct SchoolsRepo {
    db: sqlx::PgPool,
}

impl SchoolsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    // -----------------------------------------------------------------------
    // Read
    // -----------------------------------------------------------------------

    /// List all schools, optionally filtered by a search term matching name
    /// or domain (case-insensitive).
    pub async fn list_schools(&self, search: Option<&str>) -> Result<Vec<School>, AppError> {
        let schools = match search {
            Some(term) if !term.is_empty() => {
                let pattern = format!("%{}%", term);
                sqlx::query_as!(
                    School,
                    r#"SELECT id, name, domain, created_at
                       FROM schools
                       WHERE name ILIKE $1 OR domain ILIKE $1
                       ORDER BY name ASC"#,
                    pattern,
                )
                .fetch_all(&self.db)
                .await?
            }
            _ => {
                sqlx::query_as!(
                    School,
                    r#"SELECT id, name, domain, created_at
                       FROM schools
                       ORDER BY name ASC"#,
                )
                .fetch_all(&self.db)
                .await?
            }
        };
        Ok(schools)
    }

    /// Get a single school by ID.
    pub async fn find_school_by_id(&self, id: i16) -> Result<Option<School>, AppError> {
        let school = sqlx::query_as!(
            School,
            "SELECT id, name, domain, created_at FROM schools WHERE id = $1",
            id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(school)
    }

    /// Get a single school by domain.
    pub async fn find_school_by_domain(&self, domain: &str) -> Result<Option<School>, AppError> {
        let school = sqlx::query_as!(
            School,
            "SELECT id, name, domain, created_at FROM schools WHERE domain = $1",
            domain,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(school)
    }

    // -----------------------------------------------------------------------
    // Create
    // -----------------------------------------------------------------------

    /// Insert a new school. Returns the created school.
    ///
    /// Fails with `AppError::Conflict` if the domain already exists (unique
    /// constraint on `schools.domain`).
    pub async fn create_school(&self, name: &str, domain: &str) -> Result<School, AppError> {
        let school = sqlx::query_as!(
            School,
            r#"INSERT INTO schools (name, domain)
               VALUES ($1, $2)
               RETURNING id, name, domain, created_at"#,
            name,
            domain,
        )
        .fetch_one(&self.db)
        .await?;
        Ok(school)
    }

    // -----------------------------------------------------------------------
    // Update
    // -----------------------------------------------------------------------

    /// Update a school's name and/or domain. Only provided (non-None) fields
    /// are updated.
    ///
    /// Fails with `AppError::NotFound` if the school doesn't exist, or
    /// `AppError::Conflict` if the new domain conflicts with another school.
    pub async fn update_school(
        &self,
        id: i16,
        name: Option<&str>,
        domain: Option<&str>,
    ) -> Result<School, AppError> {
        let school = sqlx::query_as!(
            School,
            r#"UPDATE schools
               SET name = COALESCE($2, name),
                   domain = COALESCE($3, domain)
               WHERE id = $1
               RETURNING id, name, domain, created_at"#,
            id,
            name,
            domain,
        )
        .fetch_optional(&self.db)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("school with id {id} not found")))?;
        Ok(school)
    }

    // -----------------------------------------------------------------------
    // Delete
    // -----------------------------------------------------------------------

    /// Delete a school by ID.
    ///
    /// Fails with `AppError::NotFound` if the school doesn't exist, or
    /// `AppError::BadRequest` if any users reference this school (FK violation).
    pub async fn delete_school(&self, id: i16) -> Result<(), AppError> {
        let result = sqlx::query!("DELETE FROM schools WHERE id = $1", id)
            .execute(&self.db)
            .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound(format!("school with id {id} not found")));
        }
        Ok(())
    }
}
