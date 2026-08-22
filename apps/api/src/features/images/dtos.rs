use serde::Deserialize;
use validator::Validate;

// ---------------------------------------------------------------------------
// CM-6.1 — POST /images/presign
// ---------------------------------------------------------------------------

/// Allowed content types for listing images. Must match the B2 bucket's
/// CORS configuration and the client's image picker.
const ALLOWED_CONTENT_TYPES: &[&str] = &["image/jpeg", "image/png", "image/webp"];

#[derive(Debug, Deserialize, Validate)]
pub struct PresignRequest {
    /// The listing this image belongs to.
    pub listing_id: uuid::Uuid,

    /// MIME content type of the image the client intends to upload.
    /// Must be one of: image/jpeg, image/png, image/webp.
    #[validate(custom(function = "validate_content_type"))]
    pub content_type: String,
}

fn validate_content_type(ct: &str) -> Result<(), validator::ValidationError> {
    if ALLOWED_CONTENT_TYPES.contains(&ct) {
        Ok(())
    } else {
        Err(validator::ValidationError::new("content_type_not_allowed"))
    }
}

#[derive(serde::Serialize)]
pub struct PresignResponse {
    /// The presigned PUT URL the client should upload to directly.
    pub upload_url: String,
    /// The object key that will be stored in B2 (used later for /confirm).
    pub object_key: String,
    /// The position slot (0, 1, or 2) this image will occupy.
    pub position: i16,
}

// ---------------------------------------------------------------------------
// CM-6.2 — POST /images/confirm
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct ConfirmRequest {
    pub listing_id: uuid::Uuid,
    /// The object key returned by the presign endpoint.
    pub object_key: String,
}

#[derive(serde::Serialize)]
pub struct ConfirmResponse {
    pub id: uuid::Uuid,
    pub listing_id: uuid::Uuid,
    pub object_key: String,
    pub position: i16,
    pub created_at: time::OffsetDateTime,
}

// ---------------------------------------------------------------------------
// CM-6.3 — DELETE /images/{id} — no body, just path param
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use validator::Validate;

    #[test]
    fn jpeg_content_type_accepted() {
        let req = PresignRequest {
            listing_id: uuid::Uuid::new_v4(),
            content_type: "image/jpeg".into(),
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn png_content_type_accepted() {
        let req = PresignRequest {
            listing_id: uuid::Uuid::new_v4(),
            content_type: "image/png".into(),
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn webp_content_type_accepted() {
        let req = PresignRequest {
            listing_id: uuid::Uuid::new_v4(),
            content_type: "image/webp".into(),
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn gif_content_type_rejected() {
        let req = PresignRequest {
            listing_id: uuid::Uuid::new_v4(),
            content_type: "image/gif".into(),
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn plain_text_content_type_rejected() {
        let req = PresignRequest {
            listing_id: uuid::Uuid::new_v4(),
            content_type: "text/plain".into(),
        };
        assert!(req.validate().is_err());
    }
}
