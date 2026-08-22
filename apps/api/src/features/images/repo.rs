use uuid::Uuid;

use crate::core::error::AppError;

#[derive(Clone, Debug)]
pub struct ImagesRepo {
    db: sqlx::PgPool,
}

impl ImagesRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    // ------------------------------------------------------------------
    // CM-6.1 — Ownership + image count check before presign
    // ------------------------------------------------------------------

    /// Verify that `user_id` is the seller of `listing_id` and that the
    /// listing has room for more images (fewer than 3).
    ///
    /// Returns the next available position (0, 1, or 2), or an error if
    /// ownership fails or the listing is full.
    pub async fn check_presign_allowed(
        &self,
        listing_id: Uuid,
        user_id: Uuid,
    ) -> Result<i16, AppError> {
        // Verify the listing exists and belongs to the user
        let row = sqlx::query!("SELECT seller_id FROM listings WHERE id = $1", listing_id,)
            .fetch_optional(&self.db)
            .await?;

        let seller_id = match row {
            Some(r) => r.seller_id,
            None => return Err(AppError::NotFound("listing not found".into())),
        };

        if seller_id != user_id {
            return Err(AppError::Forbidden);
        }

        // Find the lowest available position (0, 1, or 2)
        // Positions may have gaps after deletes, so we check which are taken.
        let taken: Vec<i16> = sqlx::query_scalar!(
            "SELECT position FROM images WHERE listing_id = $1 ORDER BY position",
            listing_id,
        )
        .fetch_all(&self.db)
        .await?;

        let position = [0, 1, 2]
            .iter()
            .find(|&&p| !taken.contains(&p))
            .copied()
            .ok_or_else(|| AppError::BadRequest("listing already has 3 images".into()))?;

        Ok(position)
    }

    // ------------------------------------------------------------------
    // CM-6.2 — Confirm upload (insert into images table)
    // ------------------------------------------------------------------

    /// Register a successfully uploaded image. Called after the HEAD check
    /// against B2 confirms the object exists.
    ///
    /// Re-checks ownership and position in the same transaction to prevent
    /// TOCTOU races (two concurrent confirms for the same listing).
    pub async fn confirm_image(
        &self,
        listing_id: Uuid,
        object_key: &str,
        user_id: Uuid,
    ) -> Result<ConfirmedImage, AppError> {
        let mut tx = self.db.begin().await?;

        // Lock the listing row to prevent concurrent position allocation
        let row = sqlx::query!(
            "SELECT seller_id FROM listings WHERE id = $1 FOR UPDATE",
            listing_id,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let seller_id = match row {
            Some(r) => r.seller_id,
            None => {
                let _ = tx.rollback();
                return Err(AppError::NotFound("listing not found".into()));
            }
        };

        if seller_id != user_id {
            let _ = tx.rollback();
            return Err(AppError::Forbidden);
        }

        // Compute the next free position inside the lock
        let taken: Vec<i16> = sqlx::query_scalar!(
            "SELECT position FROM images WHERE listing_id = $1 ORDER BY position",
            listing_id,
        )
        .fetch_all(&mut *tx)
        .await?;

        let position = match [0, 1, 2].iter().find(|&&p| !taken.contains(&p)).copied() {
            Some(p) => p,
            None => {
                let _ = tx.rollback();
                return Err(AppError::BadRequest("listing already has 3 images".into()));
            }
        };

        // Insert the image row
        let row = sqlx::query!(
            "INSERT INTO images (listing_id, object_key, position)
             VALUES ($1, $2, $3)
             RETURNING id, listing_id, object_key, position, created_at",
            listing_id,
            object_key,
            position,
        )
        .fetch_one(&mut *tx)
        .await
        .map_err(AppError::from)?;

        tx.commit().await?;

        Ok(ConfirmedImage {
            id: row.id,
            listing_id: row.listing_id,
            object_key: row.object_key,
            position: row.position,
            created_at: row.created_at,
        })
    }

    // ------------------------------------------------------------------
    // CM-6.3 — Delete image (owner-only)
    // ------------------------------------------------------------------

    /// Delete an image by its ID, verifying the requester owns the listing.
    /// Returns the object_key so the caller can clean up B2.
    pub async fn delete_image(&self, image_id: Uuid, user_id: Uuid) -> Result<String, AppError> {
        let mut tx = self.db.begin().await?;

        // Join images → listings to verify ownership and get the object_key
        let row = sqlx::query!(
            "SELECT i.object_key, l.seller_id
             FROM images i
             JOIN listings l ON l.id = i.listing_id
             WHERE i.id = $1
             FOR UPDATE OF i",
            image_id,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let row = match row {
            Some(r) => r,
            None => {
                let _ = tx.rollback();
                return Err(AppError::NotFound("image not found".into()));
            }
        };

        if row.seller_id != user_id {
            let _ = tx.rollback();
            return Err(AppError::Forbidden);
        }

        sqlx::query!("DELETE FROM images WHERE id = $1", image_id)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;

        Ok(row.object_key)
    }
}

#[derive(Debug)]
pub struct ConfirmedImage {
    pub id: Uuid,
    pub listing_id: Uuid,
    pub object_key: String,
    pub position: i16,
    pub created_at: time::OffsetDateTime,
}
