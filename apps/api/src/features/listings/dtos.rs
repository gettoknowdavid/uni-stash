use serde::Deserialize;
use validator::Validate;

use crate::{
    core::{
        cursor,
        money::{Currency, Money},
    },
    features::listings::models,
};

/// Default settlement currency. Clients may override per-request; the DB
/// column defaults to NGN as well.
pub const DEFAULT_CURRENCY: Currency = Currency::NGN;

#[derive(Debug, Deserialize, serde::Serialize, Validate)]
pub struct CreateListingRequest {
    #[validate(length(min = 1, max = 200))]
    pub title: String,

    #[validate(length(max = 5000))]
    pub description: Option<String>,

    pub category_id: i16,

    /// Price in **minor units** (kobo for NGN) — never a float.
    /// ₦2,500.00 => `{ "amount_minor": 250000, "currency": "NGN" }`.
    #[validate(custom(function = "validate_money"))]
    pub price: Option<Money>,

    /// Barter-only listings (price = null): what the seller wants in exchange.
    #[validate(length(max = 1000))]
    pub barter_request: Option<String>,

    pub condition: models::Condition,
}

fn validate_money(money: &Money) -> Result<(), validator::ValidationError> {
    if money.amount_minor <= 0 {
        return Err(validator::ValidationError::new("price_must_be_positive"));
    }
    Ok(())
}

pub struct InsertListingInput<'a> {
    pub seller_id: uuid::Uuid,
    pub category_id: i16,
    pub title: &'a str,
    pub description: &'a str,
    pub price: Option<Money>,
    pub barter_request: Option<&'a str>,
    pub condition: models::Condition,
}

#[derive(serde::Serialize)]
pub struct ListingResponse {
    pub id: uuid::Uuid,
    pub seller_id: uuid::Uuid,
    pub category_id: i16,
    pub title: String,
    pub description: String,
    pub price: Option<Money>,
    pub barter_request: Option<String>,
    pub condition: models::Condition,
    pub status: models::ListingStatus,
    pub reserved_by: Option<uuid::Uuid>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub reserved_at: Option<time::OffsetDateTime>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    pub updated_at: time::OffsetDateTime,
}

impl From<models::Listing> for ListingResponse {
    fn from(listing: models::Listing) -> Self {
        let price = listing.price_money();
        ListingResponse {
            id: listing.id,
            seller_id: listing.seller_id,
            category_id: listing.category_id,
            title: listing.title,
            description: listing.description,
            price,
            barter_request: listing.barter_request,
            condition: listing.condition,
            status: listing.status,
            reserved_by: listing.reserved_by,
            reserved_at: listing.reserved_at,
            created_at: listing.created_at,
            updated_at: listing.updated_at,
        }
    }
}

#[derive(Deserialize)]
pub struct ListListingsQuery {
    /// Full-text search query. When present, results are ranked by relevance
    /// (title weighted above description) instead of recency.
    pub q: Option<String>,
    pub category: Option<i16>,
    /// Price filter bounds in **minor units** (kobo for NGN).
    pub min_price: Option<i64>,
    pub max_price: Option<i64>,
    pub status: Option<String>,
    pub seller: Option<uuid::Uuid>,
    /// Recency cursor for browse. For ranked search (`q` present) the same
    /// parameter carries the opaque ts_rank keyset cursor from the previous
    /// search response's `next_cursor`.
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(serde::Serialize)]
pub struct ListListingsResponse {
    pub listings: Vec<ListingSummary>,
    pub next_cursor: Option<String>,
}

/// Wire DTO for browse results. Built from the flat DB row so the JSON
/// always carries `price` as a Money object, never a raw integer.
#[derive(serde::Serialize)]
pub struct ListingSummary {
    pub id: uuid::Uuid,
    pub title: String,
    pub price: Option<Money>,
    pub barter_request: Option<String>,
    pub condition: models::Condition,
    pub status: models::ListingStatus,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
    /// Up to 3 photos, ordered by position. Filled in by the repo after the
    /// summary rows are fetched (single batched query), so the browse
    /// response lets clients render photo cards without an N+1 detail fetch.
    pub images: Vec<ImageSummary>,
}

/// DB row shape for browse queries (flat price/currency pair).
/// Also flattened into the hydrated saved-items response, so it derives
/// Serialize + Debug (the wire `ListingSummary` is built from it).
#[derive(Clone, Debug, serde::Serialize, sqlx::FromRow)]
pub struct ListingSummaryRow {
    pub id: uuid::Uuid,
    pub title: String,
    pub price: Option<i64>,
    pub currency: Currency,
    pub barter_request: Option<String>,
    pub condition: models::Condition,
    pub status: models::ListingStatus,
    pub created_at: time::OffsetDateTime,
}

impl From<ListingSummaryRow> for ListingSummary {
    fn from(row: ListingSummaryRow) -> Self {
        ListingSummary {
            price: row.price.map(|minor| Money {
                amount_minor: minor,
                currency: row.currency,
            }),
            id: row.id,
            title: row.title,
            barter_request: row.barter_request,
            condition: row.condition,
            status: row.status,
            created_at: row.created_at,
            images: Vec::new(),
        }
    }
}

/// DB row shape for ranked-search queries: the browse summary plus the
/// computed ts_rank, which the repo folds into the keyset cursor.
#[derive(Clone, Debug, sqlx::FromRow)]
pub struct ListingSummaryRankedRow {
    #[sqlx(flatten)]
    pub row: ListingSummaryRow,
    pub rank: f32,
}

pub struct ListingFilters {
    pub search_query: Option<String>,
    pub category: Option<i16>,
    pub min_price: Option<i64>,
    pub max_price: Option<i64>,
    /// Statuses to include. The default feed passes
    /// `[Active, Reserved]` (reserved cards render the RESERVED badge);
    /// an explicit `?status=` filter passes a single status.
    pub statuses: Vec<models::ListingStatus>,
    pub seller: Option<uuid::Uuid>,
    /// Sellers whose listings are hidden from this request (the caller's
    /// blocks). Empty for anonymous requests.
    pub exclude_sellers: Vec<uuid::Uuid>,
    pub cursor: Option<cursor::Cursor>,
    /// ts_rank keyset cursor for ranked-search pages (ignored for browse).
    /// `None` = first page. Unlike OFFSET, deep pages stay O(1).
    pub search_cursor: Option<cursor::SearchCursor>,
    pub limit: i64,
}

#[derive(serde::Serialize)]
pub struct ListingDetailResponse {
    pub id: uuid::Uuid,
    pub title: String,
    pub description: String,
    pub price: Option<Money>,
    pub barter_request: Option<String>,
    pub condition: models::Condition,
    pub status: models::ListingStatus,
    /// Set exactly while `status == reserved` (CHECK
    /// `reserved_fields_consistent`), so clients can tell the reserver
    /// apart from the seller on refetch.
    pub reserved_by: Option<uuid::Uuid>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub reserved_at: Option<time::OffsetDateTime>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
    /// Times the detail page has been opened by non-owners. Incremented
    /// best-effort on GET /listings/{id}, so it may briefly lag.
    pub view_count: i64,
    pub seller: SellerSummary,
    pub category: CategorySummary,
    pub images: Vec<ImageSummary>,
}

#[derive(serde::Serialize)]
pub struct SellerSummary {
    pub id: uuid::Uuid,
    pub display_name: String,
    pub email_verified: bool,
    pub domain: String,
    pub photo_url: Option<String>,
    /// Average stars across the seller's reviews (None when unrated).
    pub average_rating: Option<f64>,
    /// Total reviews received.
    pub review_count: i64,
}

#[derive(serde::Serialize)]
pub struct CategorySummary {
    pub id: i16,
    pub slug: String,
    pub label: String,
}

#[derive(serde::Serialize)]
pub struct ImageSummary {
    pub id: uuid::Uuid,
    pub url: String,
    pub position: i16,
    #[serde(skip_serializing)]
    pub listing_id: uuid::Uuid,
}

/// Raw DB row shape for an image. Internal only — never serialized
/// directly. The repo converts each row into `ImageSummary` once it has an
/// `R2Client` on hand to build the public URL.
#[derive(sqlx::FromRow)]
pub struct ImageRow {
    pub id: uuid::Uuid,
    pub object_key: String,
    pub position: i16,
    pub listing_id: uuid::Uuid,
}

impl ImageRow {
    /// Attach a public URL, producing the wire type. Pure/sync — building
    /// the URL is string formatting, not an API call (see
    /// `R2Client::public_url`).
    pub fn into_summary(self, r2: &crate::core::clients::R2Client) -> ImageSummary {
        ImageSummary {
            url: r2.public_url(&self.object_key),
            id: self.id,
            position: self.position,
            listing_id: self.listing_id,
        }
    }
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateListingRequest {
    #[validate(length(min = 1, max = 200))]
    pub title: Option<String>,

    #[validate(length(max = 5000))]
    pub description: Option<String>,

    pub category_id: Option<i16>,

    // Double-Option to distinguish absent from null:
    //   None       = field not in JSON → don't touch
    //   Some(None) = field present as null → set to NULL (barter)
    //   Some(Some(m)) = field present with value → set to m
    #[serde(default, deserialize_with = "deserialize_double_option")]
    pub price: Option<Option<Money>>,

    /// Double-Option, same semantics as `price`.
    #[serde(default, deserialize_with = "deserialize_double_option_string")]
    pub barter_request: Option<Option<String>>,

    pub condition: Option<models::Condition>,
}

fn deserialize_double_option<'de, D>(deserializer: D) -> Result<Option<Option<Money>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let val = Option::<Money>::deserialize(deserializer)?;
    Ok(Some(val))
}

fn deserialize_double_option_string<'de, D>(
    deserializer: D,
) -> Result<Option<Option<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let val = Option::<String>::deserialize(deserializer)?;
    Ok(Some(val))
}

/// Internal repo-facing patch type. Built from UpdateListingRequest in the
/// handler, keeping the double-Option unwrapping out of the repo.
pub struct ListingPatch {
    pub title: Option<String>,
    pub description: Option<String>,
    pub category_id: Option<i16>,
    /// None = don't touch, Some(None) = set null, Some(Some(m)) = set value
    pub price: Option<Option<Money>>,
    pub barter_request: Option<Option<String>>,
    pub condition: Option<models::Condition>,
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
            barter_request: None,
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
            price: Some(Money {
                amount_minor: -100,
                currency: DEFAULT_CURRENCY,
            }),
            barter_request: None,
            condition: models::Condition::Used,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn zero_price_fails_validation() {
        let req = CreateListingRequest {
            title: "Free thing".into(),
            description: None,
            category_id: 1,
            price: Some(Money::zero(DEFAULT_CURRENCY)),
            barter_request: None,
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
            price: Some(Money::from_major(100, DEFAULT_CURRENCY).unwrap()),
            barter_request: None,
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
            barter_request: Some("A used textbook".into()),
            condition: models::Condition::Fair,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn barter_request_over_1000_chars_fails_validation() {
        let req = CreateListingRequest {
            title: "Free couch".into(),
            description: None,
            category_id: 1,
            price: None,
            barter_request: Some("x".repeat(1001)),
            condition: models::Condition::Fair,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn double_option_price_absent_is_none() {
        let json = r#"{"title": "Test"}"#;
        let req: UpdateListingRequest = serde_json::from_str(json).unwrap();
        assert!(req.price.is_none(), "absent field should be outer None");
    }

    #[test]
    fn double_option_price_null_is_some_none() {
        let json = r#"{"title": "Test", "price": null, "barter_request": "A phone"}"#;
        let req: UpdateListingRequest = serde_json::from_str(json).unwrap();
        assert!(req.price.is_some(), "null field should be outer Some");
        assert!(
            req.price.unwrap().is_none(),
            "null field should be inner None"
        );
        assert_eq!(req.barter_request.unwrap(), Some("A phone".to_string()));
    }

    #[test]
    fn double_option_price_present_is_some_some() {
        let json = r#"{"title": "Test", "price": {"amount_minor": 4200, "currency": "NGN"}}"#;
        let req: UpdateListingRequest = serde_json::from_str(json).unwrap();
        assert_eq!(
            req.price,
            Some(Some(Money::new(4200, Currency::NGN).unwrap()))
        );
    }
}
