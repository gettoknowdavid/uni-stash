use actix_web::{HttpResponse, web};
use sqlx::Row;
use validator::Validate;

use crate::{
    core::{
        auth::middleware::AuthUser,
        cursor::decode_cursor,
        error::AppError,
        json,
        response::{ApiResponse, ErrorBody},
        state::AppState,
    },
    features::listings::{
        dtos::{
            CreateListingRequest, InsertListingInput, ListListingsQuery, ListListingsResponse,
            ListingFilters, ListingPatch, ListingResponse, UpdateListingRequest,
        },
        models::ListingStatus,
        state_machine,
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

    // A listing is priced OR barter-only — never both, never neither.
    if body.price.is_some() && body.barter_request.is_some() {
        return Err(AppError::ValidationError {
            field: "price".into(),
            reason: "a listing cannot have both a price and a barter request".into(),
        });
    }
    if body.price.is_none() && body.barter_request.is_none() {
        return Err(AppError::ValidationError {
            field: "price".into(),
            reason: "a listing must have either a price or a barter request".into(),
        });
    }

    let description = body.description.clone().unwrap_or_default();
    let input = InsertListingInput {
        seller_id: user.id,
        category_id: body.category_id,
        title: &body.title,
        description: &description,
        price: body.price,
        barter_request: body.barter_request.as_deref(),
        condition: body.condition.clone(),
    };
    let listing = state.listings_repo.insert_listing(&input).await?;
    Ok(
        HttpResponse::Created().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(listing),
            "listing created successfully",
        )),
    )
}

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

    let limit = query.limit.unwrap_or(20).clamp(1, 50);

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
        seller: query.seller,
        cursor,
        limit,
    };

    let (listings, next_cursor) = state.listings_repo.list(&filters).await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListListingsResponse, ErrorBody>::success(
            ListListingsResponse {
                listings,
                next_cursor,
            },
            "ok",
        )),
    )
}

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
    if detail.status == ListingStatus::Deleted && requester_id != Some(detail.seller.id) {
        return Err(AppError::NotFound("listing not found".into()));
    }

    Ok(HttpResponse::Ok().json(ApiResponse::success(detail, "ok")))
}

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
        price: body.price,
        barter_request: body.barter_request.clone(),
        condition: body.condition.clone(),
    };

    let updated = state
        .listings_repo
        .update_partial(path.into_inner(), user.id, &patch)
        .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(updated),
            "listing updated successfully",
        )),
    )
}

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
    let listing = state_machine::reserve_listing(&state.db, path.into_inner(), user.id).await?;

    // Best-effort push notification to the seller.
    if let Err(err) = state
        .push_sender
        .0
        .send_to_user(
            listing.seller_id,
            "Item Reserved",
            &format!("{} reserved your listing", user.display_name),
            Some(&[("listing_id", &listing.id.to_string())]),
        )
        .await
    {
        tracing::warn!(listing_id = %listing.id, error = %err, "push notification failed");
    }

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(listing),
            "listing reserved successfully",
        )),
    )
}

pub async fn mark_sold(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let listing_id = path.into_inner();
    let listing = state_machine::mark_sold(&state.db, listing_id, user.id).await?;

    // Best-effort push notification to the buyer (if any).
    // Query the sale_history for the buyer_id (set during mark_sold transaction).
    if let Ok(Some(r)) = sqlx::query(
        "SELECT buyer_id FROM sale_history WHERE listing_id = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(listing_id)
    .fetch_optional(&state.db)
    .await
        && let Ok(buyer_id) = r.try_get::<uuid::Uuid, _>("buyer_id")
        && let Err(err) = state
            .push_sender
            .0
            .send_to_user(
                buyer_id,
                "Item Sold",
                &format!("{} marked '{}' as sold", user.display_name, listing.title),
                Some(&[("listing_id", &listing.id.to_string())]),
            )
            .await
    {
        tracing::warn!(listing_id = %listing.id, error = %err, "push notification failed");
    }

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(listing),
            "listing marked as sold",
        )),
    )
}

pub async fn unreserve_listing(
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let listing = state_machine::unreserve(&state.db, path.into_inner(), user.id).await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(listing),
            "listing unreserved successfully",
        )),
    )
}
