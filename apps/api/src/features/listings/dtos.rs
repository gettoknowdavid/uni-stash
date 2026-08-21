use crate::features::listings::models;

#[derive(Debug, serde::Deserialize, serde::Serialize, validator::Validate)]
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
impl From<models::Listing> for ListingResponse {
    fn from(listing: models::Listing) -> Self {
        ListingResponse {
            id: listing.id,
            seller_id: listing.seller_id,
            category_id: listing.category_id,
            title: listing.title,
            description: listing.description,
            price: listing.price,
            condition: listing.condition,
            status: listing.status,
            reserved_by: listing.reserved_by,
            reserved_at: listing.reserved_at,
            created_at: listing.created_at,
            updated_at: listing.updated_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use validator::Validate;

    #[test]
    fn empty_title_fails_validation() {
        let req = CreateListingRequest {
            title: "".into(),
            description: None,
            category_id: 1,
            price: None,
            condition: models::Condition::New,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn negative_price_fails_validation() {
        let req = CreateListingRequest {
            title: "Laptop".into(),
            description: Some("Used".into()),
            category_id: 1,
            price: Some(-100),
            condition: models::Condition::Used,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn valid_request_passes_validation() {
        let req = CreateListingRequest {
            title: "Laptop".into(),
            description: Some("Used".into()),
            category_id: 1,
            price: Some(100),
            condition: models::Condition::New,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn null_price_passes_validation_barter_only() {
        let req = CreateListingRequest {
            title: "Free couch".into(),
            description: None,
            category_id: 1,
            price: None,
            condition: models::Condition::Fair,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn zero_price_passes_validation() {
        let req = CreateListingRequest {
            title: "Free thing".into(),
            description: None,
            category_id: 1,
            price: Some(0),
            condition: models::Condition::Used,
        };
        assert!(req.validate().is_ok());
    }
}
