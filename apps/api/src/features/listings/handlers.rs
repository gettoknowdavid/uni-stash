use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::{
    core::{auth::middleware::AuthUser, error::AppError, json, state::AppState},
    features::listings::{
        cursor::decode_cursor,
        dtos::{
            CreateListingRequest, InsertListingInput, ListListingsQuery, ListListingsResponse,
            ListingFilters, ListingResponse,
        },
        models::ListingStatus,
    },
};

pub async fn create_listing(
    state: web::Data<AppState>,
    body: json::ValidatedJson<CreateListingRequest>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    if !user.email_verified {
        return Err(AppError::EmailNotVerified);
    }

    body.validate()?;

    let description = body.description.clone().unwrap_or_default();
    let input = InsertListingInput {
        seller_id: user.id,
        category_id: body.category_id,
        title: &body.title,
        description: &description,
        price: body.price,
        condition: body.condition.clone(),
    };
    let listing = state.listings_repo.insert_listing(&input).await?;
    Ok(HttpResponse::Created().json(ListingResponse::from(listing)))
}

/// GET /api/v1/listings — public browse endpoint (no auth required).
///
/// Supports category/price/status filtering and cursor-based pagination.
/// Defaults: status = "active", limit = 20, capped at 50.
pub async fn list_listings(
    state: web::Data<AppState>,
    query: web::Query<ListListingsQuery>,
) -> Result<HttpResponse, AppError> {
    let status = match query.status.as_deref() {
        Some("reserved") => ListingStatus::Reserved,
        Some("sold") => ListingStatus::Sold,
        Some("deleted") => ListingStatus::Deleted,
        _ => ListingStatus::Active,
    };

    let limit = query.limit.unwrap_or(20).min(50).max(1);

    let cursor = query.cursor.as_deref().map(decode_cursor).transpose()?;

    let filters = ListingFilters {
        category: query.category,
        min_price: query.min_price,
        max_price: query.max_price,
        status,
        cursor,
        limit,
    };

    let (listings, next_cursor) = state.listings_repo.list(&filters).await?;

    Ok(HttpResponse::Ok().json(ListListingsResponse {
        listings,
        next_cursor,
    }))
}
