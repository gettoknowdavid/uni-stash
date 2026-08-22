use sqlx::QueryBuilder;
use uuid::Uuid;

use crate::{
    core::error::AppError,
    features::listings::{
        cursor::encode_cursor,
        dtos::{
            CategorySummary, ImageSummary, InsertListingInput, ListingDetailResponse,
            ListingFilters, ListingPatch, ListingSummary, SellerSummary,
        },
        models::Listing,
    },
};

#[derive(Clone, Debug)]
pub struct ListingsRepo {
    db: sqlx::PgPool,
}

impl ListingsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    pub async fn insert_listing<'e>(
        &self,
        input: &InsertListingInput<'e>,
    ) -> Result<Listing, AppError> {
        let listing = sqlx::query_as!(
            Listing,
            "INSERT INTO listings (seller_id, category_id, title, description, price, condition)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id, seller_id, category_id, title, description, price, condition, status, reserved_by, reserved_at, created_at, updated_at",
            input.seller_id,
            input.category_id,
            &input.title,
            &input.description,
            input.price,
            input.condition.to_string(),
        )
        .fetch_one(&self.db)
        .await?;
        Ok(listing)
    }

    // ----------------------------------------------------------------
    // CM-4.2 — Browse / filter with cursor pagination
    // ----------------------------------------------------------------

    /// Uses QueryBuilder for dynamic filters — compile-time .sqlx offline
    /// verification does not apply to this query (deliberate, scoped exception).
    /// Every value is still parameterised via push_bind, so no SQL injection.
    pub async fn list(
        &self,
        filters: &ListingFilters,
    ) -> Result<(Vec<ListingSummary>, Option<String>), AppError> {
        let limit = filters.limit.min(50);

        let is_search = filters.search_query.is_some();

        let mut query: QueryBuilder<sqlx::Postgres> = if is_search {
            // CM-5.1 — Full-text search: select with rank for display,
            // but only return the same columns as the non-search path.
            QueryBuilder::new(
                "SELECT l.id, l.title, l.price, l.condition, l.status, l.created_at
                 FROM listings l
                 WHERE l.status = ",
            )
        } else {
            QueryBuilder::new(
                "SELECT id, title, price, condition, status, created_at
                 FROM listings
                 WHERE status = ",
            )
        };

        query.push_bind(filters.status.to_string());

        // CM-5.1 — When a search query is present, filter by tsvector match
        // and order by relevance rank. plainto_tsquery handles stemming and
        // stop-word removal for the 'english' dictionary.
        if let Some(ref q) = filters.search_query {
            query.push(" AND l.search_vector @@ plainto_tsquery('english', ");
            query.push_bind(q.clone());
            query.push(")");
        }

        if let Some(category) = filters.category {
            if is_search {
                query.push(" AND l.category_id = ");
            } else {
                query.push(" AND category_id = ");
            }
            query.push_bind(category);
        }
        if let Some(min_price) = filters.min_price {
            if is_search {
                query.push(" AND l.price >= ");
            } else {
                query.push(" AND price >= ");
            }
            query.push_bind(min_price);
        }
        if let Some(max_price) = filters.max_price {
            if is_search {
                query.push(" AND l.price <= ");
            } else {
                query.push(" AND price <= ");
            }
            query.push_bind(max_price);
        }

        // Cursor pagination: only for non-search browse.
        // Search results are rank-ordered, so a (created_at, id) cursor
        // would produce incorrect pages. For MVP, search results use simple
        // limit-only pagination (no cursor, no next_cursor).
        if !is_search {
            if let Some(ref cursor) = filters.cursor {
                query
                    .push(" AND (created_at, id) < (")
                    .push_bind(cursor.created_at)
                    .push(", ")
                    .push_bind(cursor.id)
                    .push(")");
            }
        }

        if is_search {
            // CM-5.1 AC 2 — Order by ts_rank DESC for relevance.
            // ts_rank normalizes by document length, so shorter documents
            // don't unfairly rank higher.
            query.push(
                " ORDER BY ts_rank(l.search_vector, plainto_tsquery('english', ",
            );
            // Re-bind the search query for the ORDER BY expression.
            // Postgres will recognize this as the same parameter, but we need
            // to re-push it because QueryBuilder generates positional params.
            query.push_bind(filters.search_query.clone().unwrap());
            query.push(")) DESC, l.created_at DESC");
        } else {
            query.push(" ORDER BY created_at DESC, id DESC");
        }

        query.push(" LIMIT ");
        query.push_bind(limit + 1);

        let rows: Vec<ListingSummary> = query.build_query_as().fetch_all(&self.db).await?;

        let has_more = rows.len() as i64 > limit;
        let listings = if has_more {
            rows.into_iter().take(limit as usize).collect()
        } else {
            rows
        };

        // Search results don't use cursor pagination.
        let next_cursor = if is_search {
            None
        } else if has_more {
            let last = listings.last().expect("has_more implies non-empty");
            Some(encode_cursor(
                &crate::features::listings::cursor::ListingCursor {
                    created_at: last.created_at,
                    id: last.id,
                },
            ))
        } else {
            None
        };

        Ok((listings, next_cursor))
    }

    // ----------------------------------------------------------------
    // CM-4.3 — Detail view
    // ----------------------------------------------------------------

    /// Fetch a listing with seller, category, and images. Returns None
    /// if the listing doesn't exist.
    pub async fn find_detail_by_id(
        &self,
        listing_id: Uuid,
    ) -> Result<Option<ListingDetailResponse>, AppError> {
        let row = sqlx::query!(
            "SELECT l.id, l.title, l.description, l.price, l.condition, l.status, l.created_at,
                    u.id AS seller_id, u.display_name AS seller_display_name,
                    c.id AS category_id, c.slug AS category_slug, c.label AS category_label
             FROM listings l
             JOIN users u ON u.id = l.seller_id
             JOIN categories c ON c.id = l.category_id
             WHERE l.id = $1",
            listing_id,
        )
        .fetch_optional(&self.db)
        .await?;

        let row = match row {
            Some(r) => r,
            None => return Ok(None),
        };

        let images: Vec<ImageSummary> = sqlx::query_as!(
            ImageSummary,
            "SELECT id, object_key, position FROM images WHERE listing_id = $1 ORDER BY position",
            listing_id,
        )
        .fetch_all(&self.db)
        .await?;

        Ok(Some(ListingDetailResponse {
            id: row.id,
            title: row.title,
            description: row.description,
            price: row.price,
            condition: row.condition.into(),
            status: row.status.into(),
            created_at: row.created_at,
            seller: SellerSummary {
                id: row.seller_id,
                display_name: row.seller_display_name,
            },
            category: CategorySummary {
                id: row.category_id,
                slug: row.category_slug,
                label: row.category_label,
            },
            images,
        }))
    }

    // ----------------------------------------------------------------
    // CM-4.4 — Partial update
    // ----------------------------------------------------------------

    /// Apply a partial patch to a listing. Uses SELECT ... FOR UPDATE
    /// to prevent TOCTOU races against concurrent state transitions.
    pub async fn update_partial(
        &self,
        listing_id: Uuid,
        seller_id: Uuid,
        patch: &ListingPatch,
    ) -> Result<Listing, AppError> {
        let mut tx = self.db.begin().await?;

        // Lock and validate ownership + status
        let row = sqlx::query!(
            "SELECT seller_id, status FROM listings WHERE id = $1 FOR UPDATE",
            listing_id,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let row = match row {
            Some(r) => r,
            None => {
                let _ = tx.rollback();
                return Err(AppError::NotFound("listing not found".into()));
            }
        };

        if row.seller_id != seller_id {
            let _ = tx.rollback();
            return Err(AppError::Forbidden);
        }
        if row.status != "active" {
            let _ = tx.rollback();
            return Err(AppError::Conflict(
                "listing is not active".into(),
            ));
        }

        // Build dynamic UPDATE — only SET columns present in patch
        let mut query: QueryBuilder<sqlx::Postgres> =
            QueryBuilder::new("UPDATE listings SET updated_at = now()");

        let mut has_fields = false;

        if let Some(ref title) = patch.title {
            query.push(", title = ").push_bind(title.clone());
            has_fields = true;
        }
        if let Some(ref description) = patch.description {
            query.push(", description = ").push_bind(description.clone());
            has_fields = true;
        }
        if let Some(category_id) = patch.category_id {
            query.push(", category_id = ").push_bind(category_id);
            has_fields = true;
        }
        if let Some(ref price) = patch.price {
            match price {
                Some(val) => {
                    query.push(", price = ").push_bind(*val);
                }
                None => {
                    query.push(", price = NULL");
                }
            }
            has_fields = true;
        }
        if let Some(ref condition) = patch.condition {
            query.push(", condition = ").push_bind(condition.to_string());
            has_fields = true;
        }

        if !has_fields {
            let _ = tx.rollback();
            return Err(AppError::BadRequest("no fields to update".into()));
        }

        query.push(" WHERE id = ");
        query.push_bind(listing_id);
        query.push(
            " RETURNING id, seller_id, category_id, title, description, price, condition, status, reserved_by, reserved_at, created_at, updated_at",
        );

        let listing = query
            .build_query_as::<Listing>()
            .fetch_one(&mut *tx)
            .await?;

        tx.commit().await?;
        Ok(listing)
    }

    // ----------------------------------------------------------------
    // CM-4.5 — Soft delete
    // ----------------------------------------------------------------

    /// Soft-delete a listing by setting status = 'deleted'.
    /// Returns Ok(()) on success, or appropriate error if not found/forbidden.
    pub async fn soft_delete(&self, listing_id: Uuid, seller_id: Uuid) -> Result<(), AppError> {
        let mut tx = self.db.begin().await?;

        let row = sqlx::query!(
            "SELECT seller_id FROM listings WHERE id = $1 FOR UPDATE",
            listing_id,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let row = match row {
            Some(r) => r,
            None => {
                let _ = tx.rollback();
                return Err(AppError::NotFound("listing not found".into()));
            }
        };

        if row.seller_id != seller_id {
            let _ = tx.rollback();
            return Err(AppError::Forbidden);
        }

        sqlx::query!(
            "UPDATE listings SET status = 'deleted', reserved_by = NULL, reserved_at = NULL, updated_at = now() WHERE id = $1",
            listing_id,
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    // ----------------------------------------------------------------
    // CM-4.8 — Stale reservation cleanup
    // ----------------------------------------------------------------

    /// Find listing IDs with reservations older than `older_than_hours`.
    pub async fn find_stale_reservation_ids(
        &self,
        older_than_hours: i64,
    ) -> Result<Vec<Uuid>, AppError> {
        let ids = sqlx::query_scalar!(
            "SELECT id FROM listings
             WHERE status = 'reserved'
               AND reserved_at < now() - make_interval(hours => $1)",
            older_than_hours as i32,
        )
        .fetch_all(&self.db)
        .await?;
        Ok(ids)
    }
}
