use std::collections::HashMap;

use sqlx::QueryBuilder;
use uuid::Uuid;

use crate::{
    core::{
        clients::R2Client,
        cursor::{encode_cursor, encode_search_cursor},
        error::AppError,
        money::Currency,
    },
    features::listings::{
        dtos::{
            CategorySummary, DEFAULT_CURRENCY, ImageRow, ImageSummary, InsertListingInput,
            ListingDetailResponse, ListingFilters, ListingPatch, ListingSummary,
            ListingSummaryRankedRow, ListingSummaryRow, SellerSummary,
        },
        models::Listing,
    },
};

#[derive(Clone, Debug)]
pub struct ListingsRepo {
    db: sqlx::PgPool,
    r2: R2Client,
}

impl ListingsRepo {
    pub fn new(db: sqlx::PgPool, r2: R2Client) -> Self {
        Self { db, r2 }
    }

    pub async fn insert_listing<'e>(
        &self,
        input: &InsertListingInput<'e>,
    ) -> Result<Listing, AppError> {
        let listing = sqlx::query_as!(
            Listing,
            "INSERT INTO listings (seller_id, category_id, title, description, price, currency, barter_request, condition)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, seller_id, category_id, title, description, price, currency AS \"currency: Currency\", barter_request, condition, status, reserved_by, reserved_at, created_at, updated_at",
            input.seller_id,
            input.category_id,
            &input.title,
            &input.description,
            input.price.as_ref().map(|m| m.amount_minor),
            input.price.as_ref().map(|m| m.currency).unwrap_or(DEFAULT_CURRENCY).to_string(),
            input.barter_request,
            input.condition.to_string(),
        )
        .fetch_one(&self.db)
        .await?;
        Ok(listing)
    }

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
            // The rank expression is computed once in the SELECT and reused
            // by the WHERE keyset filter and the ORDER BY below.
            let mut query = QueryBuilder::new(
                "SELECT l.id, l.title, l.price, l.currency::TEXT AS currency, l.barter_request, l.condition, l.status, l.created_at,
                        ts_rank(l.search_vector, plainto_tsquery('english', ",
            );
            query.push_bind(filters.search_query.clone().unwrap());
            query.push(
                ")) AS rank
                 FROM listings l
                 WHERE l.status IN (",
            );
            query
        } else {
            QueryBuilder::new(
                "SELECT id, title, price, currency::TEXT AS currency, barter_request, condition, status, created_at
                 FROM listings
                 WHERE status IN (",
            )
        };

        // Bind each status (default feed: active + reserved; explicit
        // filter: a single status), comma-separated inside the IN (...).
        for (i, status) in filters.statuses.iter().enumerate() {
            if i > 0 {
                query.push(", ");
            }
            query.push_bind(status.to_string());
        }
        query.push(")");

        // When a search query is present, filter by tsvector match
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
        if let Some(seller) = filters.seller {
            if is_search {
                query.push(" AND l.seller_id = ");
            } else {
                query.push(" AND seller_id = ");
            }
            query.push_bind(seller);
        }

        // Cursor pagination: only for non-search browse.
        // Search results are rank-ordered, so a (created_at, id) cursor
        // would produce incorrect pages; search pages by a ts_rank keyset
        // cursor instead (O(1) per page, unlike OFFSET).
        if !is_search && let Some(ref cursor) = filters.cursor {
            query
                .push(" AND (created_at, id) < (")
                .push_bind(cursor.created_at)
                .push(", ")
                .push_bind(cursor.id)
                .push(")");
        }

        if is_search {
            // Keyset filter: continue strictly after the previous page's
            // last (rank, id). Ties on rank (identical documents) break by
            // id DESC, matching the ORDER BY.
            if let Some(ref cursor) = filters.search_cursor {
                query
                    .push(" AND (rank, l.id) < (")
                    .push_bind(cursor.rank)
                    .push(", ")
                    .push_bind(cursor.id)
                    .push(")");
            }
            // Order by ts_rank DESC for relevance.
            // ts_rank normalizes by document length, so shorter documents
            // don't unfairly rank higher.
            query.push(" ORDER BY rank DESC, l.id DESC");
        } else {
            query.push(" ORDER BY created_at DESC, id DESC");
        }

        query.push(" LIMIT ");
        query.push_bind(limit + 1);

        // Two row shapes: the ranked SELECT includes a computed `rank`
        // column, the browse SELECT does not — decode each with its own
        // row type (sqlx maps columns by name, so a missing `rank` on the
        // browse branch would otherwise 500 with "no column found").
        let (mut listings, last_ranked, has_more): (
            Vec<ListingSummary>,
            Option<(f32, Uuid)>,
            bool,
        ) = if is_search {
            let rows: Vec<ListingSummaryRankedRow> =
                query.build_query_as().fetch_all(&self.db).await?;
            let has_more = rows.len() as i64 > limit;
            let last = if has_more {
                rows.last().map(|r| (r.rank, r.row.id))
            } else {
                None
            };
            let listings: Vec<ListingSummary> = rows
                .iter()
                .take(limit.min(rows.len() as i64) as usize)
                .map(|row| ListingSummary::from(row.row.clone()))
                .collect();
            (listings, last, has_more)
        } else {
            let rows: Vec<ListingSummaryRow> = query.build_query_as().fetch_all(&self.db).await?;
            let has_more = rows.len() as i64 > limit;
            let listings: Vec<ListingSummary> = rows
                .iter()
                .take(limit.min(rows.len() as i64) as usize)
                .map(|row| ListingSummary::from(row.clone()))
                .collect();
            (listings, None, has_more)
        };

        // Attach each listing's photos (up to 3) in one batched query keyed
        // by listing id — never per-listing queries (N+1).
        self.attach_images(&mut listings).await?;

        // Search results carry a ts_rank keyset cursor; browse carries a
        // (created_at, id) recency cursor.
        let next_cursor = if is_search {
            if has_more {
                let (rank, id) = last_ranked.expect("has_more implies non-empty");
                Some(encode_search_cursor(&crate::core::cursor::SearchCursor {
                    rank,
                    id,
                }))
            } else {
                None
            }
        } else if has_more {
            let last = listings.last().expect("has_more implies non-empty");
            Some(encode_cursor(&crate::core::cursor::Cursor {
                created_at: last.created_at,
                id: last.id,
            }))
        } else {
            None
        };

        Ok((listings, next_cursor))
    }

    /// Attach each summary's images (up to 3, position-ordered) using one
    /// batched query — the browse endpoint's `images` field. No-op for an
    /// empty page.
    pub async fn attach_images(&self, listings: &mut [ListingSummary]) -> Result<(), AppError> {
        if listings.is_empty() {
            return Ok(());
        }

        let listing_ids: Vec<Uuid> = listings.iter().map(|l| l.id).collect();
        let images: Vec<ImageRow> = sqlx::query_as!(
            ImageRow,
            r#"SELECT i.id, i.object_key, i.position, i.listing_id
                FROM images i
                WHERE i.listing_id = ANY($1)
                ORDER BY i.listing_id, i.position"#,
            &listing_ids
        )
        .fetch_all(&self.db)
        .await?;

        let mut images_by_listing: HashMap<Uuid, Vec<ImageSummary>> =
            listing_ids.iter().map(|&id| (id, Vec::new())).collect();
        for image in images {
            let listing_id = image.listing_id;
            images_by_listing
                .entry(listing_id)
                .or_default()
                .push(image.into_summary(&self.r2));
        }
        for listing in listings {
            listing.images = images_by_listing.remove(&listing.id).unwrap_or_default();
        }

        Ok(())
    }

    /// Fetch a listing with seller, category, and images. Returns None
    /// if the listing doesn't exist.
    pub async fn find_detail_by_id(
        &self,
        listing_id: Uuid,
    ) -> Result<Option<ListingDetailResponse>, AppError> {
        let row = sqlx::query!(
            "SELECT l.id, l.title, l.description, l.price, l.currency AS \"currency: String\", l.barter_request, l.condition, l.status, l.reserved_by, l.reserved_at, l.created_at,
                    u.id AS seller_id, u.display_name AS seller_display_name, u.email_verified AS seller_email_verified, u.photo_url AS seller_photo_url,
                    sc.domain AS seller_domain,
                    c.id AS category_id, c.slug AS category_slug, c.label AS category_label
             FROM listings l
             JOIN users u ON u.id = l.seller_id
             JOIN schools sc ON sc.id = u.school_id
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

        let images: Vec<ImageRow> = sqlx::query_as!(
            ImageRow,
            "SELECT id, object_key, position, listing_id FROM images WHERE listing_id = $1 ORDER BY position",
            listing_id,
        )
        .fetch_all(&self.db)
        .await?;

        let images: Vec<ImageSummary> = images
            .into_iter()
            .map(|row| row.into_summary(&self.r2))
            .collect();

        Ok(Some(ListingDetailResponse {
            id: row.id,
            title: row.title,
            description: row.description,
            price: row.price.map(|minor| crate::core::money::Money {
                amount_minor: minor,
                currency: Currency::from_code(&row.currency)
                    .expect("currency column holds a valid ISO code"),
            }),
            barter_request: row.barter_request,
            condition: row.condition.into(),
            status: row.status.into(),
            reserved_by: row.reserved_by,
            reserved_at: row.reserved_at,
            created_at: row.created_at,
            seller: SellerSummary {
                id: row.seller_id,
                display_name: row.seller_display_name,
                email_verified: row.seller_email_verified,
                domain: row.seller_domain,
                photo_url: row.seller_photo_url,
            },
            category: CategorySummary {
                id: row.category_id,
                slug: row.category_slug,
                label: row.category_label,
            },
            images,
        }))
    }

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
                let _ = tx.rollback().await;
                return Err(AppError::NotFound("listing not found".into()));
            }
        };

        if row.seller_id != seller_id {
            let _ = tx.rollback().await;
            return Err(AppError::Forbidden);
        }
        if row.status != "active" {
            let _ = tx.rollback().await;
            return Err(AppError::Conflict("listing is not active".into()));
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
            query
                .push(", description = ")
                .push_bind(description.clone());
            has_fields = true;
        }
        if let Some(category_id) = patch.category_id {
            query.push(", category_id = ").push_bind(category_id);
            has_fields = true;
        }
        // price and barter_request are mutually exclusive — a listing
        // has either a price OR a barter request, never both.  Handle
        // them together to avoid duplicate SET clauses when the client
        // sends both fields in the same PATCH (e.g. toggling barter ON).
        match (&patch.price, &patch.barter_request) {
            // --- Barter request is being set to a value: clear price ---
            (_, Some(Some(barter_val))) => {
                query.push(", price = NULL");
                query
                    .push(", barter_request = ")
                    .push_bind(barter_val.clone());
                has_fields = true;
            }
            // --- Price is being set to a value: clear barter_request ---
            (Some(Some(money)), _) => {
                query.push(", price = ").push_bind(money.amount_minor);
                query
                    .push(", currency = ")
                    .push_bind(money.currency.to_string());
                query.push(", barter_request = NULL");
                has_fields = true;
            }
            // --- Both explicitly nulled (unlikely but valid) ---
            (Some(None), Some(None)) => {
                query.push(", price = NULL");
                query.push(", barter_request = NULL");
                has_fields = true;
            }
            // --- Only price nulled (switch to barter with no value yet) ---
            (Some(None), _) => {
                query.push(", price = NULL");
                has_fields = true;
            }
            // --- Only barter_request nulled (switch to priced with no value yet) ---
            (_, Some(None)) => {
                query.push(", barter_request = NULL");
                has_fields = true;
            }
            _ => {}
        }
        if let Some(ref condition) = patch.condition {
            query
                .push(", condition = ")
                .push_bind(condition.to_string());
            has_fields = true;
        }

        if !has_fields {
            let _ = tx.rollback().await;
            return Err(AppError::BadRequest("no fields to update".into()));
        }

        query.push(" WHERE id = ");
        query.push_bind(listing_id);
        query.push(
            " RETURNING id, seller_id, category_id, title, description, price, currency::TEXT AS currency, barter_request, condition, status, reserved_by, reserved_at, created_at, updated_at",
        );

        let listing = query
            .build_query_as::<Listing>()
            .fetch_one(&mut *tx)
            .await?;

        tx.commit().await?;
        Ok(listing)
    }

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
                let _ = tx.rollback().await;
                return Err(AppError::NotFound("listing not found".into()));
            }
        };

        if row.seller_id != seller_id {
            let _ = tx.rollback().await;
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
