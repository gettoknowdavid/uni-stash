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
            .region(aws_sdk_s3::config::Region::new("auto"))
            .endpoint_url(&config.r2_endpoint)
            .credentials_provider(credentials)
            .build();
        let inner = Arc::new(aws_sdk_s3::Client::from_conf(conf));
        let bucket = config.r2_bucket.clone();
        Self { inner, bucket }
    }
}

#[derive(Debug)]
struct ResendClientInner {
    http: reqwest::Client,
    api_key: String,
    base_url: String,
}

/// Sends transactional email via Resend's REST API.
///
/// Deliberately a 20-line wrapper instead of the `resend-rs` crate: the crate
/// is thinly maintained, and CM-3.4 only needs one call shape. The API key is
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
            r2_client: R2Client::from_config(&config),
            resend: ResendClient::new(&config)?,
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
            allowed_email_domains: Vec::new(),
            port: 8080,
            env: "test".into(),
            r2_bucket: "".into(),
            r2_access_key_id: "".into(),
            r2_secret_access_key: "".into(),
            r2_endpoint: "".into(),
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

    #[test]
    fn cloning_app_state_is_cheap_pointer_copies() {
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

    #[test]
    fn malformed_key_pem_fails_fast_at_boot() {
        let mut config = test_config();
        config.jwt_private_key = "not-a-pem".into();
        let err = AppState::new(&config, test_db()).unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[test]
    fn ws_registry_placeholder_is_lockable() {
        // Trivially true now; this test's real job is to break loudly the day
        // CM-7.1 changes the alias type and the lock semantics change.
        let state = AppState::new(&test_config(), test_db()).unwrap();
        let _guard = state.ws_registry.lock().unwrap();
    }
}
