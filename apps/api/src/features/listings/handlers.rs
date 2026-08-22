use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::{
    core::{auth::middleware::AuthUser, error::AppError, json, state::AppState},
    features::listings::{
        cursor::decode_cursor,
        dtos::{
            CreateListingRequest, InsertListingInput, ListingFilters, ListingPatch,
            ListListingsQuery, ListListingsResponse, ListingResponse, UpdateListingRequest,
        },
        models::ListingStatus,
        state_machine,
    },
};

// ---------------------------------------------------------------------------
// CM-4.1 — Create listing
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// CM-4.2 — Browse / list
// ---------------------------------------------------------------------------

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

    // CM-5.1: full-text search query — treat whitespace-only as absent.
    let search_query = query.q.as_ref().and_then(|q| {
        let trimmed = q.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    });

    // Cursor pagination is only valid for non-search browse (recency-ordered).
    // When searching by rank, cursor is ignored — results are page-limited only.
    let cursor = if search_query.is_none() {
        query.cursor.as_deref().map(decode_cursor).transpose()?
    } else {
        None
    };

    let filters = ListingFilters {
        search_query,
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

// ---------------------------------------------------------------------------
// CM-4.3 — Detail view
// ---------------------------------------------------------------------------

pub async fn get_listing_detail(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: Option<AuthUser>,
) -> Result<HttpResponse, AppError> {
    let listing_id = path.into_inner();

    let detail = state
        .listings_repo
        .find_detail_by_id(listing_id)
        .await?
        .ok_or_else(|| AppError::NotFound("listing not found".into()))?;

    // Owner-only visibility for deleted listings
    let requester_id = user.as_ref().map(|u| u.id);
    if detail.status == ListingStatus::Deleted
        && requester_id != Some(detail.seller.id)
    {
        return Err(AppError::NotFound("listing not found".into()));
    }

    Ok(HttpResponse::Ok().json(detail))
}

// ---------------------------------------------------------------------------
// CM-4.4 — Edit (owner + active-only)
// ---------------------------------------------------------------------------

pub async fn update_listing(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
    body: json::ValidatedJson<UpdateListingRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let patch = ListingPatch {
        title: body.title.clone(),
        description: body.description.clone(),
        category_id: body.category_id,
        price: body.price.clone(),
        condition: body.condition.clone(),
    };

    let updated = state
        .listings_repo
        .update_partial(path.into_inner(), user.id, &patch)
        .await?;

    Ok(HttpResponse::Ok().json(ListingResponse::from(updated)))
}

// ---------------------------------------------------------------------------
// CM-4.5 — Soft delete
// ---------------------------------------------------------------------------

pub async fn delete_listing(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    state
        .listings_repo
        .soft_delete(path.into_inner(), user.id)
        .await?;

    Ok(HttpResponse::NoContent().finish())
}

// ---------------------------------------------------------------------------
// CM-4.6 — Reserve
// ---------------------------------------------------------------------------

pub async fn reserve_listing(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    if !user.email_verified {
        return Err(AppError::EmailNotVerified);
    }

    // buyer_id derived from the authenticated user — never from the
    // request body, consistent with the "never trust the body for
    // identity" pattern used in CM-4.1.
    let listing =
        state_machine::reserve_listing(&state.db, path.into_inner(), user.id).await?;

    Ok(HttpResponse::Ok().json(ListingResponse::from(listing)))
}

// ---------------------------------------------------------------------------
// CM-4.7 — Mark sold / Unreserve
// ---------------------------------------------------------------------------

pub async fn mark_sold(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let listing =
        state_machine::mark_sold(&state.db, path.into_inner(), user.id).await?;

    Ok(HttpResponse::Ok().json(ListingResponse::from(listing)))
}

pub async fn unreserve_listing(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let listing =
        state_machine::unreserve(&state.db, path.into_inner(), user.id).await?;

    Ok(HttpResponse::Ok().json(ListingResponse::from(listing)))
}
