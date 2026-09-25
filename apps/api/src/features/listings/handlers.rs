use actix_web::{HttpResponse, web};
use sqlx::Row;
use validator::Validate;

use crate::{
    core::{
        auth::middleware::AuthUser,
        cursor::decode_cursor,
        error::AppError,
        json,
        realtime::{RealtimeEvent, listing_channel},
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
    // Default feed shows everything still on the market: active AND
    // reserved (the client renders a RESERVED badge on those cards).
    // Sold/deleted only surface through an explicit `?status=` filter.
    let statuses = match query.status.as_deref() {
        Some("reserved") => vec![ListingStatus::Reserved],
        Some("sold") => vec![ListingStatus::Sold],
        Some("deleted") => vec![ListingStatus::Deleted],
        Some(_) => vec![ListingStatus::Active],
        None => vec![ListingStatus::Active, ListingStatus::Reserved],
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

    // Browse pages by (created_at, id) cursor; ranked search pages by
    // offset — the search `next_cursor` encodes the next offset directly.
    let cursor = if search_query.is_none() {
        query.cursor.as_deref().map(decode_cursor).transpose()?
    } else {
        None
    };
    let search_offset = if search_query.is_some() {
        query.offset.map(|o| o.clamp(0, 10_000))
    } else {
        None
    };

    let filters = ListingFilters {
        search_query: search_query.clone(),
        category: query.category,
        min_price: query.min_price,
        max_price: query.max_price,
        statuses,
        seller: query.seller,
        cursor,
        search_offset,
        limit,
    };

    let (listings, next_cursor) = state.listings_repo.list(&filters).await?;

    // Ranked-search pagination: the repo always reports no cursor for
    // search, so the handler encodes the *next offset* instead — a plain
    // number, opaque to the client. A full page means there may be more;
    // a short page is the last one.
    let next_cursor = if search_query.is_some() {
        if listings.len() as i64 >= limit {
            Some(search_offset.unwrap_or(0).saturating_add(limit).to_string())
        } else {
            None
        }
    } else {
        next_cursor
    };

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
    let listing_id = path.into_inner();
    state.listings_repo.soft_delete(listing_id, user.id).await?;

    // Best-effort realtime nudge: any device with the detail page open
    // refetches and renders the owner-only "deleted" state.
    publish_listing_updated(&state, listing_id, "deleted").await;

    Ok(HttpResponse::NoContent().finish())
}

/// Publishes `listing.updated` on the listing's channel. Best-effort: the
/// REST row is the source of truth and clients refetch on any event.
async fn publish_listing_updated(
    state: &web::Data<AppState>,
    listing_id: uuid::Uuid,
    status: &str,
) {
    if let Err(err) = state
        .realtime
        .0
        .publish(
            &listing_channel(&listing_id),
            &RealtimeEvent::ListingUpdated {
                listing_id,
                status: status.to_string(),
            },
        )
        .await
    {
        tracing::warn!(
            listing_id = %listing_id,
            error = %err,
            "listing realtime publish failed"
        );
    }
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

    // Best-effort realtime nudge to anyone viewing the listing detail page.
    publish_listing_updated(&state, listing.id, "reserved").await;

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

    // Best-effort realtime nudge to anyone viewing the listing detail page.
    publish_listing_updated(&state, listing.id, "sold").await;

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

    // Best-effort realtime nudge to anyone viewing the listing detail page.
    publish_listing_updated(&state, listing.id, "active").await;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListingResponse, ErrorBody>::success(
            ListingResponse::from(listing),
            "listing unreserved successfully",
        )),
    )
}
