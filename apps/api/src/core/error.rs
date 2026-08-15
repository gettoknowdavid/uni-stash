use actix_web::{HttpResponse, ResponseError, http::header::ContentType};

#[derive(serde::Serialize)]
struct ErrorBody<'a> {
    error: ErrorDetail<'a>,
}

#[derive(serde::Serialize)]
struct ErrorDetail<'a> {
    code: &'a str,
    message: String,
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

    #[error("Validation error on {field}: {reason}")]
    ValidationError { field: String, reason: String },

    #[error(transparent)]
    Internal(#[from] anyhow::Error),
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
            AppError::ValidationError { .. } => "validation",
            AppError::Internal { .. } => "internal_server_error",
        }
    }

    /// Returns a human-readable message suitable for the client.
    pub fn client_message(&self) -> String {
        match self {
            AppError::Internal { .. } => "internal server error".to_string(),
            other => other.to_string(),
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
            AppError::Unauthorized { .. } => actix_web::http::StatusCode::UNAUTHORIZED,
            AppError::Forbidden => actix_web::http::StatusCode::FORBIDDEN,
            AppError::ValidationError { .. } => actix_web::http::StatusCode::UNPROCESSABLE_ENTITY,
            AppError::Internal { .. } => actix_web::http::StatusCode::INTERNAL_SERVER_ERROR,
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
            other => AppError::Internal(other.into()),
        }
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
    fn other_sqlx_errors_map_to_internal() {
        let err = AppError::from(sqlx::Error::PoolTimedOut);

        assert_eq!(err.status_code(), StatusCode::INTERNAL_SERVER_ERROR);
        assert!(matches!(err, AppError::Internal(_)));
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
