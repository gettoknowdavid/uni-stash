use sqlx::QueryBuilder;

use crate::{
    core::error::AppError,
    features::listings::{
        cursor::encode_cursor,
        dtos::{InsertListingInput, ListingFilters, ListingSummary},
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

    /// Returns `(listings, next_cursor)` where `next_cursor` is `None` when
    /// there are no more pages.
    pub async fn list(
        &self,
        filters: &ListingFilters,
    ) -> Result<(Vec<ListingSummary>, Option<String>), AppError> {
        // Cap the page size at 50 to prevent abuse (per CM-4.2 AC).
        let limit = filters.limit.min(50);

        let mut query: QueryBuilder<sqlx::Postgres> = QueryBuilder::new(
            "SELECT id, title, price, condition, status, created_at
             FROM listings
             WHERE status = ",
        );
        query.push_bind(filters.status.to_string());

        if let Some(category) = filters.category {
            query.push(" AND category_id = ").push_bind(category);
        }
        if let Some(min_price) = filters.min_price {
            query.push(" AND price >= ").push_bind(min_price);
        }
        if let Some(max_price) = filters.max_price {
            query.push(" AND price <= ").push_bind(max_price);
        }

        // Keyset pagination: (created_at, id) < ($cursor_created_at, $cursor_id).
        // Postgres tuple comparison handles the tie-breaker correctly for
        // ORDER BY created_at DESC, id DESC — it is equivalent to:
        //   created_at < $ts OR (created_at = $ts AND id < $id)
        if let Some(ref cursor) = filters.cursor {
            query
                .push(" AND (created_at, id) < (")
                .push_bind(cursor.created_at)
                .push(", ")
                .push_bind(cursor.id)
                .push(")");
        }

        query.push(" ORDER BY created_at DESC, id DESC LIMIT ");

        // fetch one extra row for has_more detection
        query.push_bind(limit + 1);

        let rows: Vec<ListingSummary> = query.build_query_as().fetch_all(&self.db).await?;

        let has_more = rows.len() as i64 > limit;
        let listings = if has_more {
            rows.into_iter().take(limit as usize).collect()
        } else {
            rows
        };

        let next_cursor = if has_more {
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
}
