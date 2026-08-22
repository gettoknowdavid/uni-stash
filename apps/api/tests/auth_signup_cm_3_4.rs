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
//   AC 5 — Email failure is best-effort: signup still returns 201, user row
//          exists. The handler catches the error and logs a warning.

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
        frontend_base_url: "https://uni-stash.com".into(),
    }
}

fn test_state(pool: PgPool) -> web::Data<AppState> {
    let config = test_config();
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
    seed_school(&pool, "known.edu").await;

    let state = test_state(pool);

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

    let state = test_state(pool.clone());

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

    let state = test_state(pool.clone());

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
// AC 5 — Email failure is best-effort: signup returns 201, user row exists.
//
// With SMTP (Brevo), email sending is best-effort — the handler catches
// errors and logs a warning. Signup always succeeds even if SMTP is
// unreachable. The user can retry via POST /auth/resend-verification.
// ===========================================================================

#[sqlx::test]
async fn signup_succeeds_even_when_smtp_is_unreachable(pool: PgPool) {
    seed_school(&pool, "test.edu").await;

    // AppState::new() will accept any SMTP config — the actual connection
    // only happens when send() is called. The handler catches send errors.
    let state = test_state(pool.clone());

    let body = signup_body("carol@test.edu", "correct horse battery staple", "Carol");
    let resp = call_signup(&state, &body).await;

    // Signup succeeds (201) even though SMTP will fail on send.
    // The handler catches the error and logs a warning.
    assert_eq!(resp.status(), 201);

    // The user row was created with email_verified = false.
    let verified = user_email_verified(&pool, "carol@test.edu").await;
    assert_eq!(
        verified,
        Some(false),
        "user row must exist with email_verified = false"
    );
}
