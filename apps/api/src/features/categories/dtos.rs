/// A category record returned by `GET /api/v1/categories`.
///
/// Categories are backend/seed-managed (CM-4.9): clients only ever read the
/// list to render pickers, so this is a plain read DTO with no request types.
#[derive(Debug, serde::Serialize, sqlx::FromRow)]
pub struct CategoryResponse {
    pub id: i16,
    pub slug: String,
    pub label: String,
}

#[derive(Debug, serde::Serialize)]
pub struct ListCategoriesResponse {
    pub categories: Vec<CategoryResponse>,
}

// ---------------------------------------------------------------------------
// Create category (admin-only)
// ---------------------------------------------------------------------------

/// Request body for creating a new category.
///
/// Admin-only (CM-4.9 addendum): categories are curated taxonomy, not
/// user-generated content — see the `slug` unique constraint on the table.
#[derive(Debug, serde::Deserialize, validator::Validate)]
pub struct CreateCategoryRequest {
    /// URL-friendly unique identifier (e.g. "textbooks").
    #[validate(
        length(min = 2, max = 50, message = "slug must be 2-50 characters"),
        regex(
            path = "SLUG_RE",
            message = "slug must be lowercase letters, digits and hyphens"
        )
    )]
    pub slug: String,

    /// Human-readable name shown in the UI (e.g. "Textbooks").
    #[validate(length(min = 2, max = 80, message = "label must be 2-80 characters"))]
    pub label: String,

    /// Display order (smaller = earlier). Defaults to 0 if omitted.
    pub sort_order: Option<i16>,
}

/// Response after successfully creating a category.
#[derive(Debug, serde::Serialize)]
pub struct CreateCategoryResponse {
    pub id: i16,
    pub slug: String,
    pub label: String,
    pub message: String,
}

// ---------------------------------------------------------------------------
// Update category (admin-only)
// ---------------------------------------------------------------------------

/// Request body for updating an existing category. All fields optional —
/// only provided fields are updated.
#[derive(Debug, serde::Deserialize, validator::Validate)]
pub struct UpdateCategoryRequest {
    #[validate(
        length(min = 2, max = 50, message = "slug must be 2-50 characters"),
        regex(
            path = "SLUG_RE",
            message = "slug must be lowercase letters, digits and hyphens"
        )
    )]
    pub slug: Option<String>,

    #[validate(length(min = 2, max = 80, message = "label must be 2-80 characters"))]
    pub label: Option<String>,

    pub sort_order: Option<i16>,
}

/// Response after successfully updating a category.
#[derive(Debug, serde::Serialize)]
pub struct UpdateCategoryResponse {
    pub id: i16,
    pub slug: String,
    pub label: String,
    pub message: String,
}

/// Compiled once for the slug format validator.
static SLUG_RE: std::sync::LazyLock<regex::Regex> =
    std::sync::LazyLock::new(|| regex::Regex::new(r"^[a-z0-9]+(-[a-z0-9]+)*$").unwrap());
