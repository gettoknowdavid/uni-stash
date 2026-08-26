use actix_web::{HttpResponse, web};
use uuid::Uuid;
use validator::Validate;

use crate::{
    core::{
        auth::middleware::AuthUser,
        error::AppError,
        json,
        response::{ApiResponse, ErrorBody},
        state::AppState,
    },
    features::images::dtos::{ConfirmRequest, ConfirmResponse, PresignRequest, PresignResponse},
};

// ---------------------------------------------------------------------------
// CM-6.1 — POST /images/presign
// ---------------------------------------------------------------------------

/// Issue a presigned PUT URL for direct client → B2 upload.
///
/// The backend never proxies image bytes. Instead it hands the client a
/// short-lived URL that lets the client upload directly to Backblaze B2.
pub async fn presign_image(
    state: web::Data<AppState>,
    body: json::ValidatedJson<PresignRequest>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let listing_id = body.listing_id;
    let content_type = &body.content_type;

    // CM-6.1 AC 4 — Only the listing's owner can request a presign.
    // CM-6.1 AC 3 — Enforces max 3 images before issuing.
    let position = state
        .images_repo
        .check_presign_allowed(listing_id, user.id)
        .await?;

    // Generate a unique object key: listing_id/position_timestamp.ext
    // The key must be deterministic enough for the client to reference
    // in the /confirm call, but unique to avoid overwrites.
    let ext = match content_type.as_str() {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        _ => "bin",
    };
    let timestamp = time::OffsetDateTime::now_utc().unix_timestamp();
    let object_key = format!("listings/{listing_id}/{position}_{timestamp}.{ext}");

    let upload_url = state
        .r2_client
        .presign_put(&object_key, content_type)
        .await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<PresignResponse, ErrorBody>::success(
        PresignResponse {
            upload_url,
            object_key,
            position,
        },
        "presigned url generated",
    )))
}

// ---------------------------------------------------------------------------
// CM-6.2 — POST /images/confirm
// ---------------------------------------------------------------------------

/// Confirm that a client upload landed in B2, then register the image.
///
/// The client calls this after completing the PUT to the presigned URL.
/// The server performs a HEAD check against B2 to verify the object exists
/// and is within size limits before inserting the DB row.
pub async fn confirm_image(
    state: web::Data<AppState>,
    body: web::Json<ConfirmRequest>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let listing_id = body.listing_id;
    let object_key = &body.object_key;

    // CM-6.2 AC 3 — HEAD check against B2 to confirm the object exists
    // and is within size limits. This is the key integrity guard — we
    // never trust that the presigned URL was actually used.
    state.r2_client.head_object_size(object_key).await?;

    // CM-6.2 AC 4 — Ownership is re-checked inside the repo transaction.
    let confirmed = state
        .images_repo
        .confirm_image(listing_id, object_key, user.id)
        .await?;

    Ok(HttpResponse::Created().json(ApiResponse::<ConfirmResponse, ErrorBody>::success(
        ConfirmResponse {
            id: confirmed.id,
            listing_id: confirmed.listing_id,
            object_key: confirmed.object_key,
            position: confirmed.position,
            created_at: confirmed.created_at,
        },
        "image confirmed successfully",
    )))
}

// ---------------------------------------------------------------------------
// CM-6.3 — DELETE /images/{id}
// ---------------------------------------------------------------------------

/// Delete an image by ID. Only the listing owner can delete.
///
/// Deletes the DB row (source of truth) and best-effort deletes the B2
/// object. B2 cleanup failures are logged but don't fail the request.
pub async fn delete_image(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let image_id = path.into_inner();

    // CM-6.3 AC 2 — Delete DB row and get the object_key back.
    let object_key = state.images_repo.delete_image(image_id, user.id).await?;

    // Best-effort B2 cleanup — the DB row is gone, so the listing is
    // consistent regardless of whether B2 delete succeeds.
    state.r2_client.delete_object(&object_key).await;

    Ok(HttpResponse::NoContent().finish())
}
