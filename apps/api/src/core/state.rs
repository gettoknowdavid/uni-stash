use jsonwebtoken::{DecodingKey, EncodingKey};
use std::sync::{Arc, Mutex};

use crate::core::{config::Config, db::Db, error::AppError};

#[derive(Clone, Debug)]
pub struct JwtKeys {
    pub encoding: Arc<EncodingKey>,
    pub decoding: Arc<DecodingKey>,
}
impl JwtKeys {
    pub fn from_pem(private_pem: &str, public_pem: &str) -> anyhow::Result<Self, AppError> {
        let encoding = EncodingKey::from_rsa_pem(private_pem.as_bytes())
            .map_err(|e| AppError::Internal(anyhow::anyhow!("invalid JWT private key PEM: {e}")))?;
        let decoding = DecodingKey::from_rsa_pem(public_pem.as_bytes())
            .map_err(|e| AppError::Internal(anyhow::anyhow!("invalid JWT public key PEM: {e}")))?;
        Ok(Self {
            encoding: Arc::new(encoding),
            decoding: Arc::new(decoding),
        })
    }
}

#[derive(Clone, Debug)]
pub struct R2Client {
    pub inner: Arc<aws_sdk_s3::Client>,
    pub bucket: String,
}
impl R2Client {
    pub fn from_config(config: &Config) -> Self {
        let credentials = aws_sdk_s3::config::Credentials::new(
            &config.r2_access_key_id,
            &config.r2_secret_access_key,
            None,
            None,
            "r2",
        );
        let conf = aws_sdk_s3::config::Builder::new()
            // aws-sdk-s3 >= 1.14x requires an explicit behavior major version
            // when constructing a client; latest() pins us to current semantics
            // rather than an SDK default that could change under us.
            .behavior_version(aws_sdk_s3::config::BehaviorVersion::latest())
            .region(aws_sdk_s3::config::Region::new("auto"))
            .endpoint_url(&config.r2_endpoint)
            .credentials_provider(credentials)
            .build();
        let inner = Arc::new(aws_sdk_s3::Client::from_conf(conf));
        let bucket = config.r2_bucket.clone();
        Self { inner, bucket }
    }
}

/// Inner state for [`ResendClient`]. Fields were previously
/// `#[allow(dead_code)]` until `send_verification_email` landed.
#[derive(Debug)]
struct ResendClientInner {
    http: reqwest::Client,
    api_key: String,
    base_url: String,
}

/// Sends transactional email via Resend's REST API.
///
/// Deliberately a thin wrapper instead of the `resend-rs` crate: the crate
/// is thinly maintained, and we only need one call shape. The API key is
/// kept behind an `Arc` and never `Debug`-printed.
#[derive(Clone, Debug)]
pub struct ResendClient(Arc<ResendClientInner>);

impl ResendClient {
    pub fn new(config: &Config) -> anyhow::Result<Self, AppError> {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .map_err(|e| AppError::Internal(anyhow::anyhow!("failed to build HTTP client: {e}")))?;
        Ok(Self(Arc::new(ResendClientInner {
            http,
            api_key: config.resend_api_key.clone(),
            base_url: config.resend_base_url.clone(),
        })))
    }

    /// Sends a verification email with a magic link.
    ///
    /// # Rollback vs. retry decision
    ///
    /// We do **not** roll back the user row on Resend failure. Instead:
    /// - The user exists with `email_verified = false`.
    /// - A future `POST /api/v1/auth/resend-verification` endpoint (not in
    ///   this ticket's scope) will let the client re-trigger the email.
    /// - Rolling back requires a transaction that spans an external HTTP
    ///   call, which is fragile and introduces distributed-transaction
    ///   semantics. Leaving the row and surfacing a 500 lets the client
    ///   retry signup (which hits the Conflict path for the duplicate email)
    ///   or lets a dedicated resend-email endpoint handle it.
    pub async fn send_verification_email(
        &self,
        to_email: &str,
        verify_token: &str,
        frontend_base_url: &str,
    ) -> Result<(), AppError> {
        let verification_url = format!(
            "{}/verify-email?token={}",
            frontend_base_url.trim_end_matches('/'),
            verify_token,
        );

        let html = format!(
            "<p>Click the link below to verify your email address:</p>\n\n\n<p><a href=\"{verification_url}\">Verify email</a></p>\n\n\n<p>This link expires in 24 hours.</p>"
        );
        let text = format!(
            "Verify your email by visiting this link:\n\n{verification_url}\n\nThis link expires in 24 hours."
        );

        let body = serde_json::json!({
            "from": "UniStash <onboarding@resend.dev>",
            "to": [to_email],
            "subject": "Verify your UniStash email",
            "html": html,
            "text": text,
        });

        let url = format!("{}/emails", self.0.base_url);
        let response = self
            .0
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.0.api_key))
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, to = to_email, "Resend request failed");
                AppError::Internal(anyhow::anyhow!("failed to send verification email: {e}"))
            })?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            tracing::error!(
                status = %status,
                body = %text,
                to = to_email,
                "Resend returned non-2xx"
            );
            return Err(AppError::Internal(anyhow::anyhow!(
                "verification email failed: HTTP {status}"
            )));
        }

        tracing::info!(to = to_email, "Verification email sent");
        Ok(())
    }
}

/// PLACEHOLDER for the chat session registry.
pub type WsRegistry = Arc<Mutex<()>>;

#[derive(Clone, Debug)]
pub struct AppState {
    pub db: sqlx::PgPool,
    pub jwt_keys: JwtKeys,
    pub r2_client: R2Client,
    pub resend: ResendClient,
    pub ws_registry: WsRegistry,
}
impl AppState {
    pub fn new(config: &Config, db: Db) -> anyhow::Result<Self, AppError> {
        Ok(Self {
            db: db.pool,
            jwt_keys: JwtKeys::from_pem(&config.jwt_private_key, &config.jwt_public_key)?,
            r2_client: R2Client::from_config(config),
            resend: ResendClient::new(config)?,
            ws_registry: Arc::new(Mutex::new(())),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Fixture keypair: 2048-bit RSA PEM committed under tests/fixtures/ (shared
    // with CM-3.2's tests). Never a real secret — same rule as CM-3.2 AC 5.
    const TEST_PRIVATE_PEM: &str = include_str!("../../tests/fixtures/test_rsa_private.pem");
    const TEST_PUBLIC_PEM: &str = include_str!("../../tests/fixtures/test_rsa_public.pem");

    // Minimal Config with all fields set to test values; mirrors the helper
    // pattern already used in core/config.rs tests.
    fn test_config() -> Config {
        Config {
            database_url: "postgres://localhost:5432/uni_stash".into(),
            jwt_private_key: TEST_PRIVATE_PEM.into(),
            jwt_public_key: TEST_PUBLIC_PEM.into(),
            resend_api_key: "https://api.resend.com".into(),
            resend_base_url: "https://api.resend.com".into(),
            port: 8080,
            env: "test".into(),
            r2_bucket: "".into(),
            r2_access_key_id: "".into(),
            r2_secret_access_key: "".into(),
            r2_endpoint: "".into(),
            frontend_base_url: "https://uni-stash.com".into(),
        }
    }

    // connect_lazy: builds a PgPool WITHOUT opening a connection — perfect
    // for unit tests that only need the type to exist.
    fn test_db() -> Db {
        Db {
            pool: sqlx::postgres::PgPoolOptions::new()
                .connect_lazy("postgres://localhost:5432/uni_stash")
                .unwrap(),
        }
    }

    // connect_lazy still needs a Tokio context in sqlx 0.9 (it sizes the pool
    // against the runtime), so these run under the actix-rt test runtime like
    // the rest of the core tests.
    #[actix_rt::test]
    async fn cloning_app_state_is_cheap_pointer_copies() {
        let state = AppState::new(&test_config(), test_db()).unwrap();
        let copy = state.clone();

        // Proves AC 3: clone is Arc-pointer bumps, not deep copies.
        assert!(Arc::ptr_eq(
            &state.jwt_keys.encoding,
            &copy.jwt_keys.encoding
        ));
        assert!(Arc::ptr_eq(
            &state.jwt_keys.decoding,
            &copy.jwt_keys.decoding
        ));
        assert!(Arc::ptr_eq(&state.r2_client.inner, &copy.r2_client.inner));
        assert!(Arc::ptr_eq(&state.resend.0, &copy.resend.0));
        assert!(Arc::ptr_eq(&state.ws_registry, &copy.ws_registry));
        // db is PgPool — Arc-backed by sqlx, cheap by construction.
    }

    #[actix_rt::test]
    async fn malformed_key_pem_fails_fast_at_boot() {
        let mut config = test_config();
        config.jwt_private_key = "not-a-pem".into();
        let err = AppState::new(&config, test_db()).unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[actix_rt::test]
    async fn ws_registry_placeholder_is_lockable() {
        // Trivially true now; this test's real job is to break loudly the day
        // CM-7.1 changes the alias type and the lock semantics change.
        let state = AppState::new(&test_config(), test_db()).unwrap();
        let _guard = state.ws_registry.lock().unwrap();
    }

    // ------------------------------------------------------------------
    // send_verification_email tests
    // ------------------------------------------------------------------

    /// Helper: build a ResendClient pointed at the given mock server URL.
    fn resend_client(base_url: &str) -> ResendClient {
        let http = reqwest::Client::new();
        ResendClient(Arc::new(ResendClientInner {
            http,
            api_key: "re_test_key".into(),
            base_url: base_url.into(),
        }))
    }

    #[actix_rt::test]
    async fn send_verification_email_success() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .and(wiremock::matchers::header(
                "Authorization",
                "Bearer re_test_key",
            ))
            .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(
                serde_json::json!({"id": "test-email-id"}),
            ))
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        let result = client
            .send_verification_email(
                "alice@example.com",
                "tok_abc123",
                "https://uni-stash.com",
            )
            .await;

        assert!(result.is_ok());
    }

    #[actix_rt::test]
    async fn send_verification_email_non_2xx_returns_error() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .respond_with(
                wiremock::ResponseTemplate::new(422).set_body_json(
                    serde_json::json!({"statusCode": 422, "message": "Invalid email"}),
                ),
            )
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        let result = client
            .send_verification_email(
                "bad@example.com",
                "tok_abc123",
                "https://uni-stash.com",
            )
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[actix_rt::test]
    async fn send_verification_email_includes_correct_url() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(
                serde_json::json!({"id": "test-email-id"}),
            ))
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        client
            .send_verification_email(
                "bob@test.com",
                "tok_xyz789",
                "https://uni-stash.com/",
            )
            .await
            .unwrap();

        // The mock was mounted with expect(1) — if it wasn't called, the test
        // would fail. But let's also verify the body contains the right URL.
        let requests = mock.received_requests().await.unwrap();
        assert_eq!(requests.len(), 1);

        let body: serde_json::Value =
            serde_json::from_slice(&requests[0].body).unwrap();
        let html = body["html"].as_str().unwrap();
        // Trailing slash on frontend_base_url should be trimmed.
        assert!(
            html.contains("https://uni-stash.com/verify-email?token=tok_xyz789"),
            "HTML should contain the verification URL, got: {html}"
        );
    }

    #[actix_rt::test]
    async fn send_verification_email_connection_refused() {
        // Port 1 is closed on every platform — simulates Resend being down.
        let client = resend_client("http://127.0.0.1:1");
        let result = client
            .send_verification_email(
                "alice@example.com",
                "tok_abc123",
                "https://uni-stash.com",
            )
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
