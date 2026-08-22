use utoipa::ToSchema;

// ---------------------------------------------------------------------------
// Request DTOs
// ---------------------------------------------------------------------------

/// Request body for creating a new school.
///
/// Only accessible by admin users. The domain must be unique — it's used to
/// match signup email addresses to their school.
#[derive(Debug, serde::Deserialize, validator::Validate, ToSchema)]
pub struct CreateSchoolRequest {
    /// Human-readable school name (e.g. "University of Port Harcourt").
    #[validate(length(min = 2, max = 200, message = "name must be 2-200 characters"))]
    #[schema(value_type = String, min_length = 2, max_length = 200, example = "University of Port Harcourt")]
    pub name: String,

    /// Email domain used for signup matching (e.g. "uniport.edu.ng").
    /// Must be unique across all schools.
    #[validate(length(min = 3, max = 253, message = "domain must be 3-253 characters"))]
    #[schema(value_type = String, min_length = 3, max_length = 253, example = "uniport.edu.ng")]
    pub domain: String,
}

/// Request body for updating an existing school.
///
/// All fields are optional — only provided fields are updated.
#[derive(Debug, serde::Deserialize, validator::Validate, ToSchema)]
pub struct UpdateSchoolRequest {
    /// New name (if changing).
    #[validate(length(min = 2, max = 200, message = "name must be 2-200 characters"))]
    #[schema(value_type = Option<String>, min_length = 2, max_length = 200)]
    pub name: Option<String>,

    /// New domain (if changing). Must be unique.
    #[validate(length(min = 3, max = 253, message = "domain must be 3-253 characters"))]
    #[schema(value_type = Option<String>, min_length = 3, max_length = 253)]
    pub domain: Option<String>,
}

// ---------------------------------------------------------------------------
// Response DTOs
// ---------------------------------------------------------------------------

/// A school record returned by list/get endpoints.
#[derive(Debug, serde::Serialize, ToSchema)]
pub struct SchoolResponse {
    pub id: i16,
    pub name: String,
    pub domain: String,
    pub created_at: String,
}

/// Response after successfully creating a school.
#[derive(Debug, serde::Serialize, ToSchema)]
pub struct CreateSchoolResponse {
    pub id: i16,
    pub name: String,
    pub domain: String,
    pub message: String,
}

/// Paginated list of schools.
#[derive(Debug, serde::Serialize, ToSchema)]
pub struct ListSchoolsResponse {
    pub schools: Vec<SchoolResponse>,
}

/// Query parameters for listing schools.
#[derive(Debug, serde::Deserialize, utoipa::IntoParams)]
pub struct ListSchoolsQuery {
    /// Optional search term to filter by name or domain.
    #[serde(rename = "q")]
    pub search: Option<String>,
}
