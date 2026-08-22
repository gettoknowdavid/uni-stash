use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::core::error::AppError;

pub struct LockedListingRow {
    pub id: Uuid,
    pub seller_id: Uuid,
    pub status: String,
    pub reserved_by: Option<Uuid>,
}

/// Lock a listing row for update within the given transaction.
/// Returns `None` if the listing does not exist.
pub async fn lock_listing_row(
    tx: &mut Transaction<'_, Postgres>,
    listing_id: Uuid,
) -> Result<Option<LockedListingRow>, AppError> {
    sqlx::query_as!(
        LockedListingRow,
        "SELECT id, seller_id, status, reserved_by FROM listings WHERE id = $1 FOR UPDATE",
        listing_id,
    )
    .fetch_optional(&mut **tx)
    .await
    .map_err(AppError::from)
}

/// Reserve an active listing for a buyer. Uses SELECT ... FOR UPDATE to
/// prevent concurrent race conditions (TRD §4.3).
pub async fn reserve_listing(
    pool: &sqlx::PgPool,
    listing_id: Uuid,
    buyer_id: Uuid,
) -> Result<crate::features::listings::models::Listing, AppError> {
    let mut tx = pool.begin().await?;

    let row = match lock_listing_row(&mut tx, listing_id).await? {
        Some(r) => r,
        None => {
            let _ = tx.rollback().await;
            return Err(AppError::NotFound("listing not found".into()));
        }
    };

    if row.status != "active" {
        let _ = tx.rollback().await;
        return Err(AppError::Conflict("listing is no longer available".into()));
    }
    if row.seller_id == buyer_id {
        let _ = tx.rollback().await;
        return Err(AppError::BadRequest(
            "cannot reserve your own listing".into(),
        ));
    }

    let listing = sqlx::query_as!(
        crate::features::listings::models::Listing,
        "UPDATE listings
         SET status = 'reserved', reserved_by = $1, reserved_at = now(), updated_at = now()
         WHERE id = $2
         RETURNING id, seller_id, category_id, title, description, price, condition as \"condition: _\", status as \"status: _\", reserved_by, reserved_at, created_at, updated_at",
        buyer_id,
        listing_id,
    )
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(listing)
}

/// Mark a reserved listing as sold. Only the seller can do this.
pub async fn mark_sold(
    pool: &sqlx::PgPool,
    listing_id: Uuid,
    seller_id: Uuid,
) -> Result<crate::features::listings::models::Listing, AppError> {
    let mut tx = pool.begin().await?;

    let row = match lock_listing_row(&mut tx, listing_id).await? {
        Some(r) => r,
        None => {
            let _ = tx.rollback().await;
            return Err(AppError::NotFound("listing not found".into()));
        }
    };

    if row.status != "reserved" {
        let _ = tx.rollback().await;
        return Err(AppError::Conflict(
            "listing must be reserved to mark as sold".into(),
        ));
    }
    if row.seller_id != seller_id {
        let _ = tx.rollback().await;
        return Err(AppError::Forbidden);
    }

    // The CHECK constraint `reserved_fields_consistent` requires reserved_by/
    // reserved_at to be NULL when status != 'reserved'. We clear them here
    // to satisfy the constraint. If "who bought it" history is desired,
    // add a separate `sale_history` table rather than fighting the schema.
    let listing = sqlx::query_as!(
        crate::features::listings::models::Listing,
        "UPDATE listings
         SET status = 'sold', reserved_by = NULL, reserved_at = NULL, updated_at = now()
         WHERE id = $1
         RETURNING id, seller_id, category_id, title, description, price, condition as \"condition: _\", status as \"status: _\", reserved_by, reserved_at, created_at, updated_at",
        listing_id,
    )
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(listing)
}

/// Unreserve a listing back to active. Only the seller or the reserving
/// buyer can do this.
pub async fn unreserve(
    pool: &sqlx::PgPool,
    listing_id: Uuid,
    requester_id: Uuid,
) -> Result<crate::features::listings::models::Listing, AppError> {
    let mut tx = pool.begin().await?;

    let row = match lock_listing_row(&mut tx, listing_id).await? {
        Some(r) => r,
        None => {
            let _ = tx.rollback().await;
            return Err(AppError::NotFound("listing not found".into()));
        }
    };

    if row.status != "reserved" {
        let _ = tx.rollback().await;
        return Err(AppError::Conflict("listing is not reserved".into()));
    }
    if requester_id != row.seller_id && Some(requester_id) != row.reserved_by {
        let _ = tx.rollback().await;
        return Err(AppError::Forbidden);
    }

    let listing = sqlx::query_as!(
        crate::features::listings::models::Listing,
        "UPDATE listings
         SET status = 'active', reserved_by = NULL, reserved_at = NULL, updated_at = now()
         WHERE id = $1
         RETURNING id, seller_id, category_id, title, description, price, condition as \"condition: _\", status as \"status: _\", reserved_by, reserved_at, created_at, updated_at",
        listing_id,
    )
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(listing)
}

/// System-initiated unreserve for stale reservations (CM-4.8).
/// Skips requester-identity check since this is a background job action.
pub async fn unreserve_system(
    pool: &sqlx::PgPool,
    listing_id: Uuid,
) -> Result<crate::features::listings::models::Listing, AppError> {
    let mut tx = pool.begin().await?;

    let row = match lock_listing_row(&mut tx, listing_id).await? {
        Some(r) => r,
        None => {
            let _ = tx.rollback().await;
            return Err(AppError::NotFound("listing not found".into()));
        }
    };

    if row.status != "reserved" {
        let _ = tx.rollback().await;
        return Err(AppError::Conflict("listing is not reserved".into()));
    }

    let listing = sqlx::query_as!(
        crate::features::listings::models::Listing,
        "UPDATE listings
         SET status = 'active', reserved_by = NULL, reserved_at = NULL, updated_at = now()
         WHERE id = $1
         RETURNING id, seller_id, category_id, title, description, price, condition as \"condition: _\", status as \"status: _\", reserved_by, reserved_at, created_at, updated_at",
        listing_id,
    )
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(listing)
}
