use actix_web::{HttpResponse, ResponseError, http::header::ContentType};

#[derive(serde::Serialize)]
struct ErrorBody<'a> {
    error: ErrorDetail<'a>,
}

#[derive(serde::Serialize)]
struct ErrorDetail<'a> {
    code: &'a str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    fields: Option<&'a [FieldError]>,
}

/// OpenAPI-compatible error response shape. Used in `#[utoipa::path]`
/// annotations since `AppError` itself can't derive `ToSchema` (it
/// contains `anyhow::Error`).
#[derive(serde::Serialize, utoipa::ToSchema)]
pub struct ErrorResponse {
    /// Machine-readable error code
    pub error: ErrorResponseBody,
}

#[derive(serde::Serialize, utoipa::ToSchema)]
pub struct ErrorResponseBody {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fields: Option<Vec<FieldError>>,
}

/// A single field-level validation error, serialised inside the
/// `fields` array of the JSON response body.
///
/// Example response when multiple fields fail validation:
///
/// ```json
/// {
///   "error": {
///     "code": "validation",
///     "message": "Validation failed",
///     "fields": [
///       {"field": "email", "message": "Must be a valid email"},
///       {"field": "password", "message": "Must be at least 10 characters"}
///     ]
///   }
/// }
/// ```
#[derive(Clone, Debug, serde::Serialize, utoipa::ToSchema)]
pub struct FieldError {
    #[schema(example = "email")]
    pub field: String,
    #[schema(example = "Must be a valid email")]
    pub message: String,
}

impl std::fmt::Display for FieldError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.field, self.message)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Access denied")]
    Forbidden,

    #[error("Token expired")]
    TokenExpired,

    #[error("Email not verified")]
    EmailNotVerified,

    #[error("Validation error on {field}: {reason}")]
    ValidationError { field: String, reason: String },

    /// Multi-field validation failure (e.g. from `validator::Validate`).
    ///
    /// Both this and the single-field [`AppError::ValidationError`] share
    /// the `"validation"` code and `422` status. This variant adds the
    /// `fields` array so the client can display per-field messages for
    /// every failing constraint simultaneously.
    #[error("Validation failed")]
    ValidationErrors(Vec<FieldError>),

    #[error("Too many requests")]
    TooManyRequests,

    #[error(transparent)]
    Internal(#[from] anyhow::Error),

    /// Raw sqlx error pass-through. Use this with `.map_err(AppError::Database)`
    /// when you want to preserve the original error without the smart mapping
    /// that `From<sqlx::Error>` provides (RowNotFound → NotFound, etc.).
    #[error("{0}")]
    Database(sqlx::Error),
}

impl AppError {
    /// Returns a machine-readable error code suitable for the client.
    pub fn code(&self) -> &'static str {
        match self {
            AppError::NotFound { .. } => "not_found",
            AppError::BadRequest { .. } => "bad_request",
            AppError::Conflict { .. } => "conflict",
            AppError::Unauthorized { .. } => "unauthorized",
            AppError::Forbidden => "forbidden",
            AppError::TokenExpired => "token_expired",
            AppError::TooManyRequests => "too_many_requests",
            AppError::EmailNotVerified => "email_not_verified",
            AppError::ValidationError { .. } | AppError::ValidationErrors(_) => "validation",
            AppError::Internal { .. } => "internal_server_error",
            AppError::Database(_) => "database_error",
        }
    }

    /// Returns a human-readable message suitable for the client.
    pub fn client_message(&self) -> String {
        match self {
            AppError::TooManyRequests => "too many requests".to_string(),
            AppError::Internal { .. } => "internal server error".to_string(),
            AppError::Database(_) => "database error".to_string(),
            AppError::ValidationErrors(_) => "Validation failed".to_string(),
            other => other.to_string(),
        }
    }

    /// Returns the field-level errors when this is a validation variant,
    /// or `None` otherwise.
    fn fields(&self) -> Option<&[FieldError]> {
        match self {
            AppError::ValidationErrors(v) => Some(v),
            _ => None,
        }
    }
}

impl ResponseError for AppError {
    fn error_response(&self) -> HttpResponse {
        if matches!(self, AppError::Internal { .. }) {
            tracing::error!(error = ?self, "internal error");
        }
        HttpResponse::build(self.status_code())
            .insert_header(ContentType::json())
            .body(
                serde_json::to_string(&ErrorBody {
                    error: ErrorDetail {
                        code: self.code(),
                        message: self.client_message(),
                        fields: self.fields(),
                    },
                })
                .unwrap_or_else(|_| {
                    r#"{"error":{"code":"internal","message":"internal server error"}}"#.to_string()
                }),
            )
    }

    fn status_code(&self) -> actix_web::http::StatusCode {
        match self {
            AppError::NotFound { .. } => actix_web::http::StatusCode::NOT_FOUND,
            AppError::BadRequest { .. } => actix_web::http::StatusCode::BAD_REQUEST,
            AppError::Conflict { .. } => actix_web::http::StatusCode::CONFLICT,
            AppError::Unauthorized { .. } | AppError::TokenExpired { .. } => {
                actix_web::http::StatusCode::UNAUTHORIZED
            }
            AppError::Forbidden | AppError::EmailNotVerified => {
                actix_web::http::StatusCode::FORBIDDEN
            }
            AppError::TooManyRequests => actix_web::http::StatusCode::TOO_MANY_REQUESTS,
            AppError::ValidationError { .. } | AppError::ValidationErrors(_) => {
                actix_web::http::StatusCode::UNPROCESSABLE_ENTITY
            }
            AppError::Internal { .. } | AppError::Database(_) => {
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => AppError::NotFound("resource not found".to_string()),
            sqlx::Error::Database(e) if e.is_unique_violation() => {
                AppError::Conflict("resource already exists".to_string())
            }
            sqlx::Error::Database(e) if e.is_foreign_key_violation() => {
                AppError::BadRequest("referenced resource does not exist".to_string())
            }
            other => AppError::Internal(other.into()),
        }
    }
}

/// Converts `validator`'s multi-field error into our typed
/// [`AppError::ValidationErrors`].
///
/// Handlers can use this with the `?` operator:
///
/// ```ignore
/// req.validate()?;
/// ```
///
/// Only field-level errors are surfaced; global errors (the `errors()` map
/// on `ValidationErrors`) are folded into the message string since
/// they don't have a specific field to point at.
impl From<validator::ValidationErrors> for AppError {
    fn from(err: validator::ValidationErrors) -> Self {
        let mut fields: Vec<FieldError> = Vec::new();

        for (field, field_errs) in err.field_errors() {
            for field_err in field_errs {
                let message = field_err
                    .message
                    .as_ref()
                    .map(|m| m.to_string())
                    .unwrap_or_else(|| format!("failed {} validation", field_err.code));
                fields.push(FieldError {
                    field: field.to_string(),
                    message,
                });
            }
        }

        if fields.is_empty() {
            // Only global errors present — surface them as a single
            // synthetic entry so the client still gets a 422.
            fields.push(FieldError {
                field: "_global".to_string(),
                message: err.to_string(),
            });
        }

        AppError::ValidationErrors(fields)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::http::StatusCode;

    #[actix_web::test]
    async fn every_variant_maps_to_status_code_and_json_shape() {
        let cases: Vec<(AppError, StatusCode, &str, &str)> = vec![
            (
                AppError::NotFound("listing 123".to_string()),
                StatusCode::NOT_FOUND,
                "not_found",
                "Not found: listing 123",
            ),
            (
                AppError::BadRequest("invalid input".to_string()),
                StatusCode::BAD_REQUEST,
                "bad_request",
                "Bad request: invalid input",
            ),
            (
                AppError::Conflict("listing already reserved".to_string()),
                StatusCode::CONFLICT,
                "conflict",
                "Conflict: listing already reserved",
            ),
            (
                AppError::Unauthorized("token expired".to_string()),
                StatusCode::UNAUTHORIZED,
                "unauthorized",
                "Unauthorized: token expired",
            ),
            (
                AppError::Forbidden,
                StatusCode::FORBIDDEN,
                "forbidden",
                "Access denied",
            ),
            (
                AppError::TokenExpired,
                StatusCode::UNAUTHORIZED,
                "token_expired",
                "Token expired",
            ),
            (
                AppError::ValidationError {
                    field: "email".to_string(),
                    reason: "invalid format".to_string(),
                },
                StatusCode::UNPROCESSABLE_ENTITY,
                "validation",
                "Validation error on email: invalid format",
            ),
            (
                AppError::Internal(anyhow::anyhow!("db exploded")),
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_server_error",
                "internal server error",
            ),
        ];

        for (err, expected_status, expected_code, expected_message) in cases {
            let resp = err.error_response();

            assert_eq!(resp.status(), expected_status, "status for {expected_code}");
            assert_eq!(
                resp.headers()
                    .get(actix_web::http::header::CONTENT_TYPE)
                    .map(|value| value.to_str().unwrap()),
                Some("application/json"),
                "content type for {expected_code}"
            );

            let body = actix_web::body::to_bytes(resp.into_body()).await.unwrap();
            let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
            assert_eq!(json["error"]["code"], expected_code);
            assert_eq!(json["error"]["message"], expected_message);
            // None of these base variants should emit a `fields` key.
            assert!(
                json["error"]["fields"].is_null(),
                "fields must be absent for {expected_code}"
            );
        }
    }

    #[actix_web::test]
    async fn internal_error_never_leaks_detail() {
        let err = AppError::Internal(anyhow::anyhow!("underlying secret detail"));

        let resp = err.error_response();
        let body = String::from_utf8(
            actix_web::body::to_bytes(resp.into_body())
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();

        assert!(
            !body.contains("underlying secret detail"),
            "body leaked internals: {body}"
        );
        assert!(body.contains("internal server error"));
    }

    #[test]
    fn sqlx_row_not_found_maps_to_not_found() {
        let err = AppError::from(sqlx::Error::RowNotFound);

        assert_eq!(err.status_code(), StatusCode::NOT_FOUND);
        assert!(matches!(err, AppError::NotFound(_)));
    }

    #[test]
    fn sqlx_unique_violation_maps_to_conflict() {
        let db_err: Box<dyn sqlx::error::DatabaseError> = Box::new(UniqueViolationDbError);
        let err = AppError::from(sqlx::Error::Database(db_err));

        assert_eq!(err.status_code(), StatusCode::CONFLICT);
        assert!(matches!(err, AppError::Conflict(_)));
    }

    #[test]
    fn sqlx_fk_violation_maps_to_bad_request() {
        let db_err: Box<dyn sqlx::error::DatabaseError> = Box::new(ForeignKeyViolationDbError);
        let err = AppError::from(sqlx::Error::Database(db_err));

        assert_eq!(err.status_code(), StatusCode::BAD_REQUEST);
        assert!(matches!(err, AppError::BadRequest(_)));
    }

    #[test]
    fn other_sqlx_errors_map_to_internal() {
        let err = AppError::from(sqlx::Error::PoolTimedOut);

        assert_eq!(err.status_code(), StatusCode::INTERNAL_SERVER_ERROR);
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[test]
    fn database_variant_preserves_raw_error() {
        let err = AppError::Database(sqlx::Error::PoolTimedOut);

        assert_eq!(err.status_code(), StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(err.code(), "database_error");
        assert!(matches!(err, AppError::Database(_)));
    }

    // ------------------------------------------------------------------
    // ValidationErrors variant
    // ------------------------------------------------------------------

    #[actix_web::test]
    async fn validation_errors_emits_fields_array_and_422() {
        let err = AppError::ValidationErrors(vec![
            FieldError {
                field: "email".to_string(),
                message: "Must be a valid email".to_string(),
            },
            FieldError {
                field: "password".to_string(),
                message: "Must be at least 10 characters".to_string(),
            },
        ]);

        assert_eq!(err.status_code(), StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(err.code(), "validation");

        let resp = err.error_response();
        let body = actix_web::body::to_bytes(resp.into_body()).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

        assert_eq!(json["error"]["code"], "validation");
        assert_eq!(json["error"]["message"], "Validation failed");

        let fields = json["error"]["fields"].as_array().unwrap();
        assert_eq!(fields.len(), 2);
        assert_eq!(fields[0]["field"], "email");
        assert_eq!(fields[0]["message"], "Must be a valid email");
        assert_eq!(fields[1]["field"], "password");
        assert_eq!(fields[1]["message"], "Must be at least 10 characters");
    }

    #[actix_web::test]
    async fn validation_errors_single_field_emits_one_element_fields_array() {
        let err = AppError::ValidationErrors(vec![FieldError {
            field: "title".to_string(),
            message: "cannot be blank".to_string(),
        }]);

        let resp = err.error_response();
        let body = actix_web::body::to_bytes(resp.into_body()).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let fields = json["error"]["fields"].as_array().unwrap();
        assert_eq!(fields.len(), 1);
        assert_eq!(fields[0]["field"], "title");
    }

    #[actix_web::test]
    async fn single_field_validation_error_has_no_fields_key() {
        let err = AppError::ValidationError {
            field: "email".to_string(),
            reason: "invalid format".to_string(),
        };

        let resp = err.error_response();
        let body = actix_web::body::to_bytes(resp.into_body()).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert!(json["error"]["fields"].is_null());
    }

    #[test]
    fn from_validator_validation_errors_converts_field_errors() {
        use validator::Validate;

        #[derive(validator::Validate)]
        struct Signup {
            #[validate(email(message = "must be a valid email"))]
            email: String,

            #[validate(length(min = 10, message = "must be at least 10 characters"))]
            password: String,
        }

        let bad = Signup {
            email: "not-an-email".into(),
            password: "short".into(),
        };

        let val_err = bad.validate().unwrap_err();
        let app_err: AppError = val_err.into();

        assert_eq!(app_err.status_code(), StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(app_err.code(), "validation");

        // Pattern-match to extract the fields vec.
        if let AppError::ValidationErrors(fields) = &app_err {
            // Both fields should appear; order may vary since HashMap is
            // unordered, so collect into a set.
            let field_names: std::collections::HashSet<&str> =
                fields.iter().map(|f| f.field.as_str()).collect();
            assert!(field_names.contains("email"));
            assert!(field_names.contains("password"));
            assert_eq!(fields.len(), 2);
        } else {
            panic!("expected ValidationErrors variant, got: {app_err:?}");
        }
    }

    #[test]
    fn from_validator_validation_errors_single_field() {
        use validator::Validate;

        #[derive(validator::Validate)]
        struct OnlyEmail {
            #[validate(email)]
            email: String,
        }

        let bad = OnlyEmail {
            email: "nope".into(),
        };
        let val_err = bad.validate().unwrap_err();
        let app_err: AppError = val_err.into();

        if let AppError::ValidationErrors(fields) = &app_err {
            assert_eq!(fields.len(), 1);
            assert_eq!(fields[0].field, "email");
            assert!(!fields[0].message.is_empty());
        } else {
            panic!("expected ValidationErrors variant");
        }
    }

    /// Minimal `DatabaseError` impl used to exercise the foreign-key-violation
    /// mapping without needing a live database.
    #[derive(Debug)]
    struct ForeignKeyViolationDbError;

    impl std::fmt::Display for ForeignKeyViolationDbError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(f, "foreign key constraint fails")
        }
    }

    impl std::error::Error for ForeignKeyViolationDbError {}

    impl sqlx::error::DatabaseError for ForeignKeyViolationDbError {
        fn message(&self) -> &str {
            "foreign key constraint fails"
        }

        fn kind(&self) -> sqlx::error::ErrorKind {
            sqlx::error::ErrorKind::ForeignKeyViolation
        }

        fn as_error(&self) -> &(dyn std::error::Error + Send + Sync + 'static) {
            self
        }

        fn as_error_mut(&mut self) -> &mut (dyn std::error::Error + Send + Sync + 'static) {
            self
        }

        fn into_error(self: Box<Self>) -> Box<dyn std::error::Error + Send + Sync + 'static> {
            self
        }
    }

    /// Minimal `DatabaseError` impl used to exercise the unique-violation
    /// mapping without needing a live database.
    #[derive(Debug)]
    struct UniqueViolationDbError;

    impl std::fmt::Display for UniqueViolationDbError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(f, "duplicate key value violates unique constraint")
        }
    }

    impl std::error::Error for UniqueViolationDbError {}

    impl sqlx::error::DatabaseError for UniqueViolationDbError {
        fn message(&self) -> &str {
            "duplicate key value violates unique constraint"
        }

        fn kind(&self) -> sqlx::error::ErrorKind {
            sqlx::error::ErrorKind::UniqueViolation
        }

        fn as_error(&self) -> &(dyn std::error::Error + Send + Sync + 'static) {
            self
        }

        fn as_error_mut(&mut self) -> &mut (dyn std::error::Error + Send + Sync + 'static) {
            self
        }

        fn into_error(self: Box<Self>) -> Box<dyn std::error::Error + Send + Sync + 'static> {
            self
        }
    }
}
