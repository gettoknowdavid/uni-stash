use crate::{
    core::error::AppError,
    features::listings::{dtos::InsertListingInput, models::Listing},
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
}
