use std::future::Future;
use std::ops::{Deref, DerefMut};
use std::pin::Pin;

use actix_web::dev::Payload;
use actix_web::FromRequest;
use actix_web::HttpRequest;

use crate::core::error::{AppError, FieldError};

/// A JSON body extractor that maps serde deserialization failures into
/// [`AppError::ValidationErrors`] (422) instead of actix's default
/// `JsonPayloadError` response.
///
/// Drop-in replacement for [`actix_web::web::Json<T>`]: identical API surface
/// (`Deref<T>`, `DerefMut<T>`), but the `FromRequest` error type is
/// [`AppError`], so handlers can return `Result<HttpResponse, AppError>`
/// and always get the project's consistent error shape.
///
/// # Example
///
/// ```ignore
/// use crate::core::json::ValidatedJson;
///
/// pub async fn create_listing(
///     body: ValidatedJson<CreateListingRequest>,
/// ) -> Result<HttpResponse, AppError> {
///     // `body` derefs to `CreateListingRequest` — no other changes needed.
///     body.validate()?;
///     // ...
/// }
/// ```
pub struct ValidatedJson<T>(actix_web::web::Json<T>);

impl<T: std::fmt::Debug> std::fmt::Debug for ValidatedJson<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl<T> ValidatedJson<T> {
    /// Returns the inner deserialized value.
    pub fn into_inner(self) -> T {
        self.0.into_inner()
    }
}

impl<T> Deref for ValidatedJson<T> {
    type Target = T;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl<T> DerefMut for ValidatedJson<T> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl<T: serde::de::DeserializeOwned + 'static> FromRequest for ValidatedJson<T> {
    type Error = AppError;
    type Future = Pin<Box<dyn Future<Output = Result<Self, Self::Error>>>>;

    fn from_request(req: &HttpRequest, payload: &mut Payload) -> Self::Future {
        // Delegate the heavy lifting (content-type check, body collection,
        // JSON parse) to actix's built-in Json extractor, then convert its
        // error type into ours.
        let fut = actix_web::web::Json::<T>::from_request(req, payload);
        Box::pin(async move {
            match fut.await {
                Ok(json) => Ok(ValidatedJson(json)),
                Err(json_err) => {
                    let msg = json_err.to_string();
                    Err(json_payload_error_to_app_error(&msg))
                }
            }
        })
    }
}

/// Map actix's `JsonPayloadError` message into our structured
/// [`AppError`] shape, surfacing the serde error detail.
fn json_payload_error_to_app_error(msg: &str) -> AppError {
    // serde "unknown variant `X`, expected ..." → surface the variant name.
    if let Some(variant) = extract_unknown_variant(msg) {
        return AppError::ValidationErrors(vec![FieldError {
            field: "_body".to_string(),
            message: format!("unknown variant `{variant}`"),
        }]);
    }

    // Any other deserialization error (missing field, wrong type, etc.)
    // → single synthetic field error so the client still gets a 422.
    AppError::ValidationErrors(vec![FieldError {
        field: "_body".to_string(),
        message: msg.to_string(),
    }])
}

/// Try to pull the variant name out of a serde "unknown variant" error
/// message like `unknown variant \`X\`, expected one of ...`.
fn extract_unknown_variant(msg: &str) -> Option<&str> {
    let marker = "unknown variant `";
    let start = msg.find(marker)? + marker.len();
    let end = msg[start..].find('`')?;
    Some(&msg[start..start + end])
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::http::StatusCode;
    use actix_web::test as actix_test;
    use actix_web::{web, App, HttpResponse};

    // ---- Types used by tests ----

    #[derive(Debug, serde::Deserialize, serde::Serialize)]
    struct SimpleRequest {
        name: String,
    }

    #[derive(Debug, serde::Deserialize, serde::Serialize, PartialEq)]
    #[serde(rename_all = "lowercase")]
    enum Color {
        Red,
        Blue,
    }

    // ---- Test handlers ----

    async fn echo_simple(body: ValidatedJson<SimpleRequest>) -> Result<HttpResponse, AppError> {
        Ok(HttpResponse::Ok().json(body.name.clone()))
    }

    async fn echo_color(body: ValidatedJson<Color>) -> Result<HttpResponse, AppError> {
        Ok(HttpResponse::Ok().json(format!("{body:?}")))
    }

    // ---- Tests ----

    #[actix_web::test]
    async fn valid_json_deserializes_ok() {
        let app = actix_test::init_service(
            App::new().route("/", web::post().to(echo_simple)),
        )
        .await;

        let req = actix_test::TestRequest::post()
            .uri("/")
            .set_json(serde_json::json!({"name": "hello"}))
            .to_request();

        let resp = actix_test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn invalid_json_returns_422_validation_error() {
        let app = actix_test::init_service(
            App::new().route("/", web::post().to(echo_simple)),
        )
        .await;

        let req = actix_test::TestRequest::post()
            .uri("/")
            .insert_header(("content-type", "application/json"))
            .set_payload(r#"{"wrong_field":"hello"}"#)
            .to_request();

        let resp = actix_test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

        let body: serde_json::Value = actix_test::read_body_json(resp).await;
        assert_eq!(body["error"]["code"], "validation");
        let fields = body["error"]["fields"].as_array().unwrap();
        assert_eq!(fields[0]["field"], "_body");
    }

    #[actix_web::test]
    async fn unknown_enum_variant_surfaces_variant_name() {
        let app = actix_test::init_service(
            App::new().route("/", web::post().to(echo_color)),
        )
        .await;

        // "broken" is not a valid Color variant
        let req = actix_test::TestRequest::post()
            .uri("/")
            .insert_header(("content-type", "application/json"))
            .set_payload(r#""broken""#)
            .to_request();

        let resp = actix_test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

        let body: serde_json::Value = actix_test::read_body_json(resp).await;
        assert_eq!(body["error"]["code"], "validation");
        let fields = body["error"]["fields"].as_array().unwrap();
        assert!(
            fields[0]["message"]
                .as_str()
                .unwrap()
                .contains("broken"),
            "expected variant name in error message, got: {}",
            fields[0]["message"]
        );
    }

    #[actix_web::test]
    async fn malformed_json_returns_422() {
        let app = actix_test::init_service(
            App::new().route("/", web::post().to(echo_simple)),
        )
        .await;

        let req = actix_test::TestRequest::post()
            .uri("/")
            .insert_header(("content-type", "application/json"))
            .set_payload("not json at all")
            .to_request();

        let resp = actix_test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

        let body: serde_json::Value = actix_test::read_body_json(resp).await;
        assert_eq!(body["error"]["code"], "validation");
    }

    #[actix_web::test]
    async fn missing_content_type_produces_422() {
        // actix's Json extractor rejects missing content-type;
        // our wrapper surfaces it as a validation error.
        let app = actix_test::init_service(
            App::new().route("/", web::post().to(echo_simple)),
        )
        .await;

        let req = actix_test::TestRequest::post()
            .uri("/")
            .set_payload(r#"{"name":"hi"}"#)
            .to_request();

        let resp = actix_test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

        let body: serde_json::Value = actix_test::read_body_json(resp).await;
        assert_eq!(body["error"]["code"], "validation");
    }

    #[test]
    fn extract_unknown_variant_parses_correctly() {
        let msg = "unknown variant `broken`, expected one of `red`, `blue`";
        assert_eq!(extract_unknown_variant(msg), Some("broken"));

        let no_variant = "unexpected end of JSON input";
        assert_eq!(extract_unknown_variant(no_variant), None);
    }
}
