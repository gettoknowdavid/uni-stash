use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Public shape of a user profile, served by `GET /api/v1/users/{id}`.
/// Contains only what's safe to expose to other students — never email,
/// deletion state, or preference flags.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PublicUserProfile {
    pub id: Uuid,
    pub display_name: String,
    pub photo_url: Option<String>,
    /// School email domain, e.g. "unilag.edu.ng".
    pub domain: String,
    #[serde(with = "time::serde::rfc3339")]
    pub joined_at: time::OffsetDateTime,
}

/// Profile + rating summary + public listing stats, all in one response so
/// the profile page renders without extra round-trips.
#[derive(Debug, Serialize)]
pub struct PublicProfileResponse {
    #[serde(flatten)]
    pub profile: PublicUserProfile,
    /// Average stars across the user's received reviews (None = unrated).
    pub average_rating: Option<f64>,
    pub review_count: i64,
    /// Active + reserved listings count (what's publicly visible).
    pub active_listings: i64,
}

#[derive(Serialize)]
pub struct PublicProfileListingsResponse {
    pub listings: Vec<crate::features::listings::dtos::ListingSummary>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UserListingsQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}
