use std::sync::{Arc, Mutex};

use crate::{
    core::{
        clients::{JwtKeys, R2Client, ResendClient},
        config::Config,
        db::Db,
        error::AppError,
        rate_limit::PerEmailLimiter,
    },
    features::{auth::repo::AuthRepo, listings::repo::ListingsRepo},
};

/// PLACEHOLDER for the chat session registry.
pub type WsRegistry = Arc<Mutex<()>>;

#[derive(Clone, Debug)]
pub struct AppState {
    pub db: sqlx::PgPool,
    pub jwt_keys: JwtKeys,
    pub r2_client: R2Client,
    pub resend: ResendClient,
    pub ws_registry: WsRegistry,
    pub auth_repo: AuthRepo,
    pub listings_repo: ListingsRepo,
    /// Per-email sliding-window rate limiter (in-memory, 30 req / 60 s).
    pub email_limiter: PerEmailLimiter,
}
impl AppState {
    pub fn new(config: &Config, db: Db) -> anyhow::Result<Self, AppError> {
        Ok(Self {
            jwt_keys: JwtKeys::from_pem(&config.jwt_private_key, &config.jwt_public_key)?,
            r2_client: R2Client::from_config(config),
            resend: ResendClient::new(config)?,
            ws_registry: Arc::new(Mutex::new(())),
            auth_repo: AuthRepo::new(db.pool.clone()),
            listings_repo: ListingsRepo::new(db.pool.clone()),
            email_limiter: PerEmailLimiter::new(),
            db: db.pool,
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
        // ResendClient clone is tested in clients::resend::tests.
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
}
