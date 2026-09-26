//! `/metrics` endpoint (Prometheus scrape) — observability acceptance.
//!
//! Contract:
//! - enabled + no token → 200 with text exposition format
//! - enabled + token set → 401 without the bearer / 200 with the right one
//! - disabled → 404

use actix_web::{App, test, web};
use uni_stash_be::core::config::Config;
use uni_stash_be::{configure_health, core};

fn config(enabled: bool, token: &str) -> Config {
    let mut config = test_config_base();
    config.metrics_enabled = enabled;
    config.metrics_token = token.to_string();
    config
}

/// Mirrors the AppState::new test fixture (fake PEM keys, no external deps).
fn test_config_base() -> Config {
    const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
    const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

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
        metrics_enabled: true,
        metrics_token: "".into(),
    }
}

#[actix_web::test]
async fn metrics_enabled_without_token_returns_200_text() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config(true, "")))
            .configure(configure_health),
    )
    .await;

    let req = test::TestRequest::get().uri("/metrics").to_request();
    let res = test::call_service(&app, req).await;

    assert_eq!(res.status(), 200);
    assert!(
        res.headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .starts_with("text/plain"),
        "content-type must be the Prometheus exposition format"
    );
    let body = test::read_body(res).await;
    let text = std::str::from_utf8(&body).unwrap();
    // render() always emits something valid — either the placeholder comment
    // (recorder not installed in this test process) or real metrics.
    assert!(
        text.contains("http_requests_total") || text.starts_with('#'),
        "unexpected metrics body: {text}"
    );
}

#[actix_web::test]
async fn metrics_with_token_rejects_missing_bearer() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config(true, "secret-token")))
            .configure(configure_health),
    )
    .await;

    let req = test::TestRequest::get().uri("/metrics").to_request();
    let res = test::call_service(&app, req).await;
    assert_eq!(res.status(), 401);
}

#[actix_web::test]
async fn metrics_with_token_accepts_correct_bearer() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config(true, "secret-token")))
            .configure(configure_health),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/metrics")
        .insert_header(("Authorization", "Bearer secret-token"))
        .to_request();
    let res = test::call_service(&app, req).await;
    assert_eq!(res.status(), 200);
}

#[actix_web::test]
async fn metrics_with_token_rejects_wrong_bearer() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config(true, "secret-token")))
            .configure(configure_health),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/metrics")
        .insert_header(("Authorization", "Bearer wrong-token"))
        .to_request();
    let res = test::call_service(&app, req).await;
    assert_eq!(res.status(), 401);
}

#[actix_web::test]
async fn metrics_disabled_returns_404() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(config(false, "")))
            .configure(configure_health),
    )
    .await;

    let req = test::TestRequest::get().uri("/metrics").to_request();
    let res = test::call_service(&app, req).await;
    assert_eq!(res.status(), 404);
}

#[actix_web::test]
async fn metrics_helpers_never_panic() {
    // Recording helpers must be safe to call before/without init (tests,
    // early boot): the metrics crate buffers observations until a recorder
    // exists, and gauge adjustments must not panic on any thread.
    core::metrics::record_http_request("GET", "/health", 200, 0.001);
    core::metrics::adjust_in_flight(1);
    core::metrics::adjust_in_flight(-1);
    core::metrics::record_db_pool_acquire(0.01);
}

#[actix_web::test]
async fn metrics_init_is_idempotent_or_fails_cleanly() {
    // Second install must return an error (recorder already set by another
    // test in this binary) OR succeed if this is the first — either way no
    // panic, and render() stays callable (empty output is valid for a fresh
    // recorder with no observations yet).
    let _ = core::metrics::init();
    let _ = core::metrics::render();
}
