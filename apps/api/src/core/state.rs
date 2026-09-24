use std::sync::Arc;

use crate::{
    core::{
        clients::{JwtKeys, R2Client, SmtpClient},
        config::Config,
        db::Db,
        error::AppError,
        rate_limit::PerEmailLimiter,
        realtime::RealtimePublisher,
    },
    features::{
        admin_auth::AdminAuthRepo, admin_management::AdminManagementRepo, auth::repo::AuthRepo,
        categories::repo::CategoriesRepo, chats::repo::ChatsRepo, images::repo::ImagesRepo,
        listings::repo::ListingsRepo, notifications::repo::NotificationsRepo,
        sales::repo::SalesRepo, saved_items::repo::SavedItemsRepo, schools::repo::SchoolsRepo,
    },
};

/// `Arc<dyn PushSender>` with a manual Debug impl (prints the
/// provider name) so `AppState` can keep `#[derive(Debug)]`.
#[derive(Clone)]
pub struct PushSenderHandle(pub std::sync::Arc<dyn crate::core::notifications::PushSender>);

impl std::fmt::Debug for PushSenderHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "PushSenderHandle({})", self.0.name())
    }
}

/// `Arc<dyn RealtimePublisher>` with a manual Debug impl (prints the
/// provider name) so `AppState` can keep `#[derive(Debug)]`.
#[derive(Clone)]
pub struct RealtimePublisherHandle(pub Arc<dyn RealtimePublisher>);

impl std::fmt::Debug for RealtimePublisherHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "RealtimePublisherHandle({})", self.0.name())
    }
}

#[derive(Clone, Debug)]
pub struct AppState {
    pub db: sqlx::PgPool,
    pub jwt_keys: JwtKeys,
    pub r2_client: R2Client,
    pub smtp: SmtpClient,
    pub auth_repo: AuthRepo,
    pub admin_auth_repo: AdminAuthRepo,
    pub admin_management_repo: AdminManagementRepo,
    pub listings_repo: ListingsRepo,
    pub images_repo: ImagesRepo,
    pub schools_repo: SchoolsRepo,
    pub categories_repo: CategoriesRepo,
    pub chats_repo: ChatsRepo,
    pub notifications_repo: NotificationsRepo,
    pub sales_repo: SalesRepo,
    pub saved_items_repo: SavedItemsRepo,
    /// Realtime event publisher (Pusher Channels for MVP). Provider is
    /// selected at boot from `REALTIME_PROVIDER`; see `core::realtime`.
    /// Manual Debug impl: `Arc<dyn Trait>` can't derive it.
    pub realtime: RealtimePublisherHandle,
    /// Push notification sender (Pusher Beams for MVP). Provider is
    /// selected at boot; see `core::notifications`.
    pub push_sender: PushSenderHandle,
    /// Per-email sliding-window rate limiter (in-memory, 30 req / 60 s).
    pub email_limiter: PerEmailLimiter,
}
impl AppState {
    pub fn new(config: &Config, db: Db) -> anyhow::Result<Self, AppError> {
        config
            .validate()
            .map_err(|e| AppError::Internal(anyhow::anyhow!("config validation failed: {e:#}")))?;

        let pool = db.pool.clone();
        let r2_client = R2Client::from_config(config);

        // Realtime publisher is built once at boot; provider-agnostic.
        let realtime = crate::core::realtime::from_config(config);
        // Push sender is built once at boot; provider-agnostic.

        Ok(Self {
            jwt_keys: JwtKeys::from_pem(&config.jwt_private_key, &config.jwt_public_key)?,
            smtp: SmtpClient::new(config)?,
            auth_repo: AuthRepo::new(pool.clone()),
            admin_auth_repo: AdminAuthRepo::new(pool.clone()),
            admin_management_repo: AdminManagementRepo::new(pool.clone()),
            listings_repo: ListingsRepo::new(pool.clone(), r2_client.clone()),
            images_repo: ImagesRepo::new(pool.clone()),
            schools_repo: SchoolsRepo::new(pool.clone()),
            categories_repo: CategoriesRepo::new(pool.clone()),
            chats_repo: ChatsRepo::new(pool.clone()),
            notifications_repo: NotificationsRepo::new(pool.clone()),
            sales_repo: SalesRepo::new(pool.clone()),
            saved_items_repo: SavedItemsRepo::new(pool.clone()),
            realtime: RealtimePublisherHandle(realtime),
            push_sender: PushSenderHandle(crate::core::notifications::from_config(config)),
            email_limiter: PerEmailLimiter::new(),
            r2_client,
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
            smtp_host: "smtp.example.com".into(),
            smtp_port: 587,
            smtp_user: "test@example.com".into(),
            smtp_password: "test_password".into(),
            smtp_from: "Test <test@example.com>".into(),
            port: 8080,
            env: "test".into(),
            r2_bucket: "".into(),
            r2_access_key_id: "".into(),
            r2_secret_access_key: "".into(),
            r2_endpoint: "".into(),
            r2_public_url_base: "".into(),
            frontend_base_url: "https://uni-stash.com".into(),
            realtime_provider: "none".into(),
            pusher_app_id: "".into(),
            pusher_key: "".into(),
            pusher_secret: "".into(),
            pusher_cluster: "".into(),
            pusher_instance_id: "".into(),
            pusher_secret_key: "".into(),
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
        // SmtpClient clone is tested in clients::smtp::tests.
        // db is PgPool — Arc-backed by sqlx, cheap by construction.
    }

    #[actix_rt::test]
    async fn malformed_key_pem_fails_fast_at_boot() {
        let mut config = test_config();
        config.jwt_private_key = "not-a-pem".into();
        let err = AppState::new(&config, test_db()).unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
