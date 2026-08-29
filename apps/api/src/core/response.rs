use actix_web::body::BoxBody;
use actix_web::http::header::ContentType;
use actix_web::{HttpRequest, HttpResponse, Responder};

// ---------------------------------------------------------------------------
// Generic API response envelope
// ---------------------------------------------------------------------------

/// Standard envelope for every API response.
///
/// ```json
/// {
///   "status": true,
///   "message": "ok",
///   "data": { ... } | null
/// }
/// ```
///
/// On error, `error` is populated and `data` is null:
///
/// ```json
/// {
///   "status": false,
///   "message": "bad request",
///   "error": {
///     "code": "validation",
///     "message": "Validation failed",
///     "fields": [ ... ]
///   }
/// }
/// ```
#[derive(serde::Serialize)]
pub struct ApiResponse<T: serde::Serialize, E: serde::Serialize = ErrorBody> {
    pub status: bool,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<E>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
}

// ---------------------------------------------------------------------------
// Success constructors
// ---------------------------------------------------------------------------

impl<T: serde::Serialize> ApiResponse<T> {
    /// 200 with data and a custom message.
    pub fn success(data: T, message: impl Into<String>) -> Self {
        ApiResponse {
            status: true,
            message: message.into(),
            error: None,
            data: Some(data),
        }
    }

    /// 200 with data and an empty/ok message.
    pub fn success_with_status(data: T) -> Self {
        ApiResponse {
            status: true,
            message: "ok".to_string(),
            error: None,
            data: Some(data),
        }
    }

    /// 200 with data only (message = "ok").
    pub fn ok(data: T) -> Self {
        Self::success_with_status(data)
    }
}

/// Message-only success response (no `data` field).
pub struct MessageOnly {
    pub message: String,
}

impl serde::Serialize for MessageOnly {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeMap;
        let mut map = serializer.serialize_map(Some(3))?;
        map.serialize_entry("status", &true)?;
        map.serialize_entry("message", &self.message)?;
        map.end()
    }
}

/// Convenience: `ApiResponse::<(), ErrorBody>::message_only("foo")`.
impl ApiResponse<(), ErrorBody> {
    pub fn message_only(message: impl Into<String>) -> Self {
        ApiResponse {
            status: true,
            message: message.into(),
            error: None,
            data: Some(()),
        }
    }
}

// ---------------------------------------------------------------------------
// Error constructors
// ---------------------------------------------------------------------------

/// The `error` object inside an error response envelope.
#[derive(serde::Serialize)]
pub struct ErrorBody {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fields: Option<Vec<ErrorField>>,
}

/// A single field-level validation error inside `ErrorBody.fields`.
#[derive(serde::Serialize)]
pub struct ErrorField {
    pub field: String,
    pub message: String,
}

impl<T: serde::Serialize> ApiResponse<T, ErrorBody> {
    /// Create a generic error response.
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> ApiResponse<T, ErrorBody> {
        ApiResponse {
            status: false,
            message: message.into(),
            error: Some(ErrorBody {
                code: code.into(),
                message: String::new(),
                fields: None,
            }),
            data: None,
        }
    }

    /// Create a validation error response with field-level details.
    pub fn validation_error(
        fields: Vec<crate::core::error::FieldError>,
    ) -> ApiResponse<T, ErrorBody> {
        ApiResponse {
            status: false,
            message: "Validation failed".to_string(),
            error: Some(ErrorBody {
                code: "validation".to_string(),
                message: "Validation failed".to_string(),
                fields: Some(
                    fields
                        .into_iter()
                        .map(|f| ErrorField {
                            field: f.field,
                            message: f.message,
                        })
                        .collect(),
                ),
            }),
            data: None,
        }
    }

    /// Create a validation error response with the error details on the error field.
    pub fn validation_error_with_detail(
        detail_message: &str,
        fields: Option<Vec<crate::core::error::FieldError>>,
    ) -> ApiResponse<T, ErrorBody> {
        ApiResponse {
            status: false,
            message: "Validation failed".to_string(),
            error: Some(ErrorBody {
                code: "validation".to_string(),
                message: detail_message.to_string(),
                fields: fields.map(|fs| {
                    fs.into_iter()
                        .map(|f| ErrorField {
                            field: f.field,
                            message: f.message,
                        })
                        .collect()
                }),
            }),
            data: None,
        }
    }
}

/// Typed error envelope for `From<AppError>` implementation.
///
/// This carries the error details in a strongly-typed way while still
/// conforming to the standard `{status, message, error}` shape.
#[derive(serde::Serialize)]
pub struct ErrorEnvelope {
    pub status: bool,
    pub message: String,
    pub error: ErrorBody,
}

impl ErrorEnvelope {
    pub fn new(
        code: &str,
        message: String,
        fields: Option<&[crate::core::error::FieldError]>,
    ) -> Self {
        ErrorEnvelope {
            status: false,
            message: message.clone(),
            error: ErrorBody {
                code: code.to_string(),
                message,
                fields: fields.map(|fs| {
                    fs.iter()
                        .map(|f| ErrorField {
                            field: f.field.clone(),
                            message: f.message.clone(),
                        })
                        .collect()
                }),
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Responder implementation
// ---------------------------------------------------------------------------

impl<T: serde::Serialize, E: serde::Serialize> Responder for ApiResponse<T, E> {
    type Body = BoxBody;

    fn respond_to(self, _req: &HttpRequest) -> HttpResponse<Self::Body> {
        HttpResponse::Ok()
            .insert_header(ContentType::json())
            .json(self)
    }
}
