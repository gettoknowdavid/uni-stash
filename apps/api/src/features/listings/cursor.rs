use base64::Engine;

use crate::core::error::AppError;

#[derive(Debug, serde::Deserialize, serde::Serialize)]
pub struct ListingCursor {
    pub created_at: time::OffsetDateTime,
    pub id: uuid::Uuid,
}

pub fn encode_cursor(cursor: &ListingCursor) -> String {
    let nanos = cursor.created_at.unix_timestamp_nanos();
    let cursor_str = format!("{}:{}", nanos, cursor.id);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(cursor_str)
}

pub fn decode_cursor(raw: &str) -> Result<ListingCursor, AppError> {
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(raw)
        .map_err(|_| AppError::BadRequest("invalid cursor".into()))?;

    let cursor_str =
        String::from_utf8(decoded).map_err(|_| AppError::BadRequest("invalid cursor".into()))?;

    let parts: Vec<&str> = cursor_str.split(':').collect();
    if parts.len() != 2 {
        return Err(AppError::BadRequest("invalid cursor".into()));
    }

    let nanos = parts[0]
        .parse::<i128>()
        .map_err(|_| AppError::BadRequest("invalid cursor".into()))?;

    let id = uuid::Uuid::parse_str(parts[1])
        .map_err(|_| AppError::BadRequest("invalid cursor".into()))?;

    Ok(ListingCursor {
        created_at: time::OffsetDateTime::from_unix_timestamp_nanos(nanos).unwrap(),
        id,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::ResponseError;

    #[test]
    fn encode_then_decode_round_trips() {
        let id = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let ts =
            time::OffsetDateTime::from_unix_timestamp_nanos(1_700_000_000_000_000_000).unwrap();
        let cursor = ListingCursor { created_at: ts, id };

        let encoded = encode_cursor(&cursor);
        let decoded = decode_cursor(&encoded).unwrap();

        assert_eq!(decoded.id, id);
        assert_eq!(
            decoded.created_at.unix_timestamp_nanos(),
            ts.unix_timestamp_nanos()
        );
    }

    #[test]
    fn decode_rejects_malformed_base64() {
        let err = decode_cursor("!!!not-base64!!!").unwrap_err();
        assert!(matches!(err, AppError::BadRequest(_)));
        assert_eq!(err.status_code(), actix_web::http::StatusCode::BAD_REQUEST);
    }

    #[test]
    fn decode_rejects_missing_colon_separator() {
        let no_colon = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode("123456789");
        let err = decode_cursor(&no_colon).unwrap_err();
        assert!(matches!(err, AppError::BadRequest(_)));
    }

    #[test]
    fn decode_rejects_bad_uuid() {
        let payload = "1234:not-a-uuid";
        let encoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(payload);
        let err = decode_cursor(&encoded).unwrap_err();
        assert!(matches!(err, AppError::BadRequest(_)));
    }

    #[test]
    fn decode_rejects_bad_timestamp() {
        let id = uuid::Uuid::new_v4();
        let payload = format!("not-a-number:{}", id);
        let encoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(payload);
        let err = decode_cursor(&encoded).unwrap_err();
        assert!(matches!(err, AppError::BadRequest(_)));
    }
}
