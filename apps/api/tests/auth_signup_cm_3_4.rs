// apps/api/tests/auth_signup_cm_3_4.rs
//
// CM-3.4 — Signup flow integration tests.
//
// Covers every acceptance criterion for the POST /api/v1/auth/signup endpoint:
//
//   AC 1 — 422 on invalid email / short password / empty display_name
//          (unit-testable against SignUpRequest::validate(), no DB)
//   AC 2 — 400 on unrecognized email domain
//   AC 3 — 201 + row inserted with email_verified = false on success
//   AC 4 — 409 on duplicate email
//   AC 5 — Resend failure → 500, user row still exists (no rollback)

use actix_web::{App, ResponseError, test, web};
use sqlx::PgPool;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::auth::dtos::SignUpRequest;
use validator::Validate;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

fn test_config(resend_base_url: &str) -> Config {
    Config {
        database_url: "postgres://localhost:5432/uni_stash".into(),
        jwt_private_key: TEST_PRIVATE_PEM.into(),
        jwt_public_key: TEST_PUBLIC_PEM.into(),
        resend_api_key: "re_test_key".into(),
        resend_base_url: resend_base_url.into(),
        port: 8080,
        env: "test".into(),
        r2_bucket: "".into(),
        r2_access_key_id: "".into(),
        r2_secret_access_key: "".into(),
        r2_endpoint: "".into(),
        frontend_base_url: "https://uni-stash.com".into(),
    }
}

fn test_state(pool: PgPool, resend_base_url: &str) -> web::Data<AppState> {
    let config = test_config(resend_base_url);
    let db = Db { pool };
    web::Data::new(AppState::new(&config, db).expect("AppState"))
}

async fn seed_school(pool: &PgPool, domain: &str) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', $1) RETURNING id",
    )
    .bind(domain)
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn user_count_by_email(pool: &PgPool, email: &str) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM users WHERE email = $1")
        .bind(email)
        .fetch_one(pool)
        .await
        .expect("count users")
}

async fn user_email_verified(pool: &PgPool, email: &str) -> Option<bool> {
    sqlx::query_scalar::<_, bool>("SELECT email_verified FROM users WHERE email = $1")
        .bind(email)
        .fetch_optional(pool)
        .await
        .expect("check email_verified")
}

fn signup_body(email: &str, password: &str, display_name: &str) -> serde_json::Value {
    serde_json::json!({
        "email": email,
        "password": password,
        "display_name": display_name,
    })
}

async fn call_signup(
    state: &web::Data<AppState>,
    body: &serde_json::Value,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/signup",
        web::post().to(uni_stash_be::features::auth::handlers::signup),
    ))
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/signup")
        .set_json(body)
        .to_request();

    test::call_service(&app, req).await
}

// ===========================================================================
// AC 1 — 422 on invalid input (no DB needed — pure DTO validation)
// ===========================================================================

#[actix_web::test]
async fn invalid_email_returns_422() {
    let req = SignUpRequest {
        email: "not-an-email".into(),
        password: "long enough password".into(),
        display_name: "Alice".into(),
    };
    let err = req.validate().unwrap_err();
    let app_err: uni_stash_be::core::error::AppError = err.into();
    assert_eq!(app_err.status_code(), 422);
    assert_eq!(app_err.code(), "validation");
}

#[actix_web::test]
async fn short_password_returns_422() {
    let req = SignUpRequest {
        email: "alice@test.edu".into(),
        password: "short".into(),
        display_name: "Alice".into(),
    };
    let err = req.validate().unwrap_err();
    let app_err: uni_stash_be::core::error::AppError = err.into();
    assert_eq!(app_err.status_code(), 422);
    assert_eq!(app_err.code(), "validation");
}

#[actix_web::test]
async fn empty_display_name_returns_422() {
    let req = SignUpRequest {
        email: "alice@test.edu".into(),
        password: "long enough password".into(),
        display_name: "".into(),
    };
    let err = req.validate().unwrap_err();
    let app_err: uni_stash_be::core::error::AppError = err.into();
    assert_eq!(app_err.status_code(), 422);
    assert_eq!(app_err.code(), "validation");
}

// ===========================================================================
// AC 2 — 400 on unrecognized email domain
// ===========================================================================

#[sqlx::test]
async fn unrecognized_domain_returns_400(pool: PgPool) {
    // Seed a school with a known domain — the signup email uses a different one.
    seed_school(&pool, "known.edu").await;

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool, &mock.uri());

    let body = signup_body("alice@unknown.edu", "long enough password", "Alice");
    let resp = call_signup(&state, &body).await;

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");
}

// ===========================================================================
// AC 3 — 201 + row inserted with email_verified = false on success
// ===========================================================================

#[sqlx::test]
async fn successful_signup_returns_201_with_email_verified_false(pool: PgPool) {
    seed_school(&pool, "test.edu").await;

    let mock = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/emails"))
        .respond_with(
            wiremock::ResponseTemplate::new(200)
                .set_body_json(serde_json::json!({"id": "email-id-123"})),
        )
        .expect(1)
        .mount(&mock)
        .await;

    let state = test_state(pool.clone(), &mock.uri());

    let body = signup_body("alice@test.edu", "correct horse battery staple", "Alice");
    let resp = call_signup(&state, &body).await;

    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["email"], "alice@test.edu");
    assert_eq!(json["display_name"], "Alice");
    assert_eq!(json["email_verified"], false);
    assert!(json["id"].is_string(), "response must include a UUID id");

    // Verify the row was actually inserted with email_verified = false.
    let verified = user_email_verified(&pool, "alice@test.edu").await;
    assert_eq!(
        verified,
        Some(false),
        "DB row must have email_verified = false"
    );
}

// ===========================================================================
// AC 4 — 409 on duplicate email
// ===========================================================================

#[sqlx::test]
async fn duplicate_email_returns_409(pool: PgPool) {
    seed_school(&pool, "test.edu").await;

    let mock = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/emails"))
        .respond_with(
            wiremock::ResponseTemplate::new(200)
                .set_body_json(serde_json::json!({"id": "email-id-123"})),
        )
        .mount(&mock)
        .await;

    let state = test_state(pool.clone(), &mock.uri());

    let body = signup_body("bob@test.edu", "correct horse battery staple", "Bob");

    // First signup succeeds.
    let resp1 = call_signup(&state, &body).await;
    assert_eq!(resp1.status(), 201);

    // Second signup with the same email → 409 Conflict.
    let resp2 = call_signup(&state, &body).await;
    assert_eq!(resp2.status(), 409);
    let json: serde_json::Value = test::read_body_json(resp2).await;
    assert_eq!(json["error"]["code"], "conflict");

    // Exactly one row exists.
    assert_eq!(
        user_count_by_email(&pool, "bob@test.edu").await,
        1,
        "duplicate insert must not create a second row"
    );
}

// ===========================================================================
// AC 5 — Resend failure → 500, user row still exists (no rollback)
// ===========================================================================

#[sqlx::test]
async fn resend_failure_returns_500_but_user_row_exists(pool: PgPool) {
    seed_school(&pool, "test.edu").await;

    // Mock Resend to return 500 — simulates an outage.
    let mock = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path("/emails"))
        .respond_with(
            wiremock::ResponseTemplate::new(500)
                .set_body_json(serde_json::json!({"message": "internal server error"})),
        )
        .expect(1)
        .mount(&mock)
        .await;

    let state = test_state(pool.clone(), &mock.uri());

    let body = signup_body("carol@test.edu", "correct horse battery staple", "Carol");
    let resp = call_signup(&state, &body).await;

    // Handler surfaces the Resend failure as a 500.
    assert_eq!(resp.status(), 500);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "internal_server_error");

    // The user row was NOT rolled back — it exists with email_verified = false.
    // This is the deliberate "allow-retry-verification" design: the client can
    // retry signup (hits 409 for the duplicate) or a future resend-verification
    // endpoint will handle it.
    let verified = user_email_verified(&pool, "carol@test.edu").await;
    assert_eq!(
        verified,
        Some(false),
        "user row must survive Resend failure with email_verified = false"
    );
}

/// Variant: Resend is completely unreachable (connection refused) → still 500,
/// user row still exists.
#[sqlx::test]
async fn resend_unreachable_returns_500_but_user_row_exists(pool: PgPool) {
    seed_school(&pool, "test.edu").await;

    // Port 1 is closed on every platform — simulates Resend being fully down.
    let state = test_state(pool.clone(), "http://127.0.0.1:1");

    let body = signup_body("dave@test.edu", "correct horse battery staple", "Dave");
    let resp = call_signup(&state, &body).await;

    assert_eq!(resp.status(), 500);

    let verified = user_email_verified(&pool, "dave@test.edu").await;
    assert_eq!(
        verified,
        Some(false),
        "user row must survive Resend connection failure with email_verified = false"
    );
}
