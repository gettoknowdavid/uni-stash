use crate::features::listings::models;

#[derive(serde::Deserialize, serde::Serialize, validator::Validate)]
pub struct CreateListingRequest {
    #[validate(length(min = 1, max = 200))]
    pub title: String,

    #[validate(length(max = 5000))]
    pub description: Option<String>,

    pub category_id: i16,

    #[validate(range(min = 0))]
    pub price: Option<i32>,

    pub condition: models::Condition,
}

pub struct InsertListingInput<'a> {
    pub seller_id: uuid::Uuid,
    pub category_id: i16,
    pub title: &'a str,
    pub description: &'a str,
    pub price: Option<i32>,
    pub condition: models::Condition,
}

#[derive(serde::Serialize)]
pub struct ListingResponse {
    pub id: uuid::Uuid,
    pub seller_id: uuid::Uuid,
    pub category_id: i16,
    pub title: String,
    pub description: String,
    pub price: Option<i32>,
    pub condition: models::Condition,
    pub status: models::ListingStatus,
    pub reserved_by: Option<uuid::Uuid>,
    pub reserved_at: Option<time::OffsetDateTime>,
    pub created_at: time::OffsetDateTime,
    pub updated_at: time::OffsetDateTime,
}
