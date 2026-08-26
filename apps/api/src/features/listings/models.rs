#[derive(Clone, Debug, PartialEq, sqlx::Type, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "lowercase")]
#[sqlx(type_name = "TEXT", rename_all = "lowercase")]
pub enum ListingStatus {
    Active,
    Reserved,
    Sold,
    Deleted,
}
impl std::fmt::Display for ListingStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ListingStatus::Active => write!(f, "active"),
            ListingStatus::Reserved => write!(f, "reserved"),
            ListingStatus::Sold => write!(f, "sold"),
            ListingStatus::Deleted => write!(f, "deleted"),
        }
    }
}
impl std::convert::From<String> for ListingStatus {
    fn from(s: String) -> Self {
        match s.as_str() {
            "active" => ListingStatus::Active,
            "reserved" => ListingStatus::Reserved,
            "sold" => ListingStatus::Sold,
            "deleted" => ListingStatus::Deleted,
            _ => ListingStatus::Active,
        }
    }
}

#[derive(Clone, Debug, PartialEq, sqlx::Type, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "lowercase")]
#[sqlx(type_name = "TEXT", rename_all = "lowercase")]
pub enum Condition {
    New,
    Used,
    Fair,
}

impl std::fmt::Display for Condition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Condition::New => write!(f, "new"),
            Condition::Used => write!(f, "used"),
            Condition::Fair => write!(f, "fair"),
        }
    }
}
impl std::convert::From<String> for Condition {
    fn from(s: String) -> Self {
        match s.as_str() {
            "new" => Condition::New,
            "used" => Condition::Used,
            "fair" => Condition::Fair,
            _ => Condition::New,
        }
    }
}

#[derive(Debug, sqlx::FromRow, serde::Serialize)]
pub struct Listing {
    pub id: uuid::Uuid,
    pub seller_id: uuid::Uuid,
    pub category_id: i16,
    pub title: String,
    pub description: String,
    pub price: Option<i32>,
    pub condition: Condition,
    pub status: ListingStatus,
    pub reserved_by: Option<uuid::Uuid>,
    pub reserved_at: Option<time::OffsetDateTime>,
    pub created_at: time::OffsetDateTime,
    pub updated_at: time::OffsetDateTime,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn listing_status_debug_and_eq() {
        let a = ListingStatus::Active;
        assert_eq!(a, ListingStatus::Active);
        assert_ne!(a, ListingStatus::Sold);
        assert_eq!(format!("{:?}", a), "Active");
    }

    #[test]
    fn condition_debug_and_eq() {
        let a = Condition::New;
        assert_eq!(a, Condition::New);
        assert_ne!(a, Condition::Used);
        assert_eq!(format!("{:?}", a), "New");
    }

    #[test]
    fn listing_status_serde_lowercase() {
        let cases = [
            (ListingStatus::Active, "\"active\""),
            (ListingStatus::Reserved, "\"reserved\""),
            (ListingStatus::Sold, "\"sold\""),
            (ListingStatus::Deleted, "\"deleted\""),
        ];
        for (variant, expected) in cases {
            let json = serde_json::to_string(&variant).unwrap();
            assert_eq!(json, expected, "ListingStatus::{:?} serialization", variant);
        }
    }

    #[test]
    fn condition_serde_lowercase() {
        let cases = [
            (Condition::New, "\"new\""),
            (Condition::Used, "\"used\""),
            (Condition::Fair, "\"fair\""),
        ];
        for (variant, expected) in cases {
            let json = serde_json::to_string(&variant).unwrap();
            assert_eq!(json, expected, "Condition::{:?} serialization", variant);
        }
    }

    #[test]
    fn listing_status_deserialize_roundtrip() {
        let originals = [
            ListingStatus::Active,
            ListingStatus::Reserved,
            ListingStatus::Sold,
            ListingStatus::Deleted,
        ];
        for original in originals {
            let json = serde_json::to_string(&original).unwrap();
            let back: ListingStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(back, original);
        }
    }

    #[test]
    fn condition_deserialize_roundtrip() {
        let originals = [Condition::New, Condition::Used, Condition::Fair];
        for original in originals {
            let json = serde_json::to_string(&original).unwrap();
            let back: Condition = serde_json::from_str(&json).unwrap();
            assert_eq!(back, original);
        }
    }
}
