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
