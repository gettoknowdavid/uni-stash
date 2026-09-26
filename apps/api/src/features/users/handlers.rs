use actix_web::{HttpResponse, web};
use uuid::Uuid;

use crate::core::{
    cursor::decode_cursor,
    error::AppError,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::listings::dtos::ListingFilters;
use crate::features::listings::models::ListingStatus;
use crate::features::users::dtos::{PublicProfileListingsResponse, PublicProfileResponse};

/// GET /api/v1/users/{user_id} — public profile: identity, rating summary,
/// and active-listing count. 404 for unknown or soft-deleted users; private
/// profiles still return identity (visibility only limits listings, per the
/// profile_visibility semantics).
pub async fn get_profile(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = path.into_inner();

    let profile = sqlx::query!(
        r#"SELECT u.id, u.display_name, u.photo_url, u.created_at,
                  sc.domain
           FROM users u
           JOIN schools sc ON sc.id = u.school_id
           WHERE u.id = $1 AND u.deleted_at IS NULL"#,
        user_id,
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("user not found".into()))?;

    let summary = state.reviews_repo.summary_for_user(user_id).await?;

    let active_listings = sqlx::query_scalar!(
        r#"SELECT COUNT(*) as "count!" FROM listings
           WHERE seller_id = $1 AND status IN ('active', 'reserved')"#,
        user_id,
    )
    .fetch_one(&state.db)
    .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<PublicProfileResponse, ErrorBody>::success(
            PublicProfileResponse {
                profile: crate::features::users::dtos::PublicUserProfile {
                    id: profile.id,
                    display_name: profile.display_name,
                    photo_url: profile.photo_url,
                    domain: profile.domain,
                    joined_at: profile.created_at,
                },
                average_rating: summary.average_rating,
                review_count: summary.review_count,
                active_listings,
            },
            "ok",
        )),
    )
}

/// GET /api/v1/users/{user_id}/listings — the user's public listings
/// (active + reserved), newest first, cursor-paginated. Reuses the browse
/// pipeline so images ride along; deleted/sold listings stay private.
pub async fn user_listings(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    query: web::Query<super::dtos::UserListingsQuery>,
) -> Result<HttpResponse, AppError> {
    let user_id = path.into_inner();

    // 404 up front for deleted/unknown users so the client can distinguish
    // "gone" from "no listings".
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)",
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;
    if !exists {
        return Err(AppError::NotFound("user not found".into()));
    }

    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let cursor = match query.cursor.as_deref() {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let filters = ListingFilters {
        search_query: None,
        category: None,
        min_price: None,
        max_price: None,
        statuses: vec![ListingStatus::Active, ListingStatus::Reserved],
        seller: Some(user_id),
        // Profiles show all their listings regardless of the viewer's blocks
        // — the block is a "don't surface in my feed" preference, and the
        // viewer chose to come here.
        exclude_sellers: Vec::new(),
        cursor,
        search_cursor: None,
        limit,
    };

    let (listings, next_cursor) = state.listings_repo.list(&filters).await?;

    Ok(HttpResponse::Ok().json(
        ApiResponse::<PublicProfileListingsResponse, ErrorBody>::success(
            PublicProfileListingsResponse {
                listings,
                next_cursor,
            },
            "ok",
        ),
    ))
}
