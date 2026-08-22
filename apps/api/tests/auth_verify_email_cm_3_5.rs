// apps/api/tests/auth_verify_email_cm_3_5.rs
//
// CM-3.5 — Verify-email flow integration tests (OTP-based).
//
// Covers every acceptance criterion for the POST /api/v1/auth/verify-otp endpoint
// with type = "email_verify":
//
//   AC 1 — Valid OTP → 200, email_verified flips to true in DB
//   AC 2 — Invalid OTP code → 400 bad_request
//   AC 3 — Expired OTP → 400 bad_request
//   AC 4 — Re-verifying an already-verified user → 200, idempotent, no error
//   AC 5 — OTP consumed after use (single-use enforcement)

use actix_web::{App, test, web};
use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::otp;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;

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

async fn insert_user(pool: &PgPool, school_id: i16, email: &str, email_verified: bool) -> Uuid {
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, $2, 'dummy_hash', 'Test User', $3)
         RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(email_verified)
    .fetch_one(pool)
    .await
    .expect("insert user")
}

async fn user_email_verified(pool: &PgPool, user_id: &Uuid) -> bool {
    sqlx::query_scalar::<_, bool>("SELECT email_verified FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .expect("check email_verified")
}

/// Generate a real OTP for the user, returning the plaintext code.
async fn generate_otp(pool: &PgPool, user_id: Uuid, otp_type: &str) -> String {
    let (code, _id) = test_state(pool.clone())
        .auth_repo
        .insert_otp(user_id, otp_type)
        .await
        .expect("insert otp");
    code
}

/// POST /api/v1/auth/verify-otp with the given code and type.
async fn call_verify_otp(
    state: &web::Data<AppState>,
    code: &str,
    otp_type: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/verify-otp",
        web::post().to(uni_stash_be::features::auth::handlers::verify_otp),
    ))
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/verify-otp")
        .set_json(serde_json::json!({ "code": code, "otp_type": otp_type }))
        .to_request();

    test::call_service(&app, req).await
}

// ===========================================================================
// AC 1 — Valid OTP → 200, email_verified flips to true in DB
// ===========================================================================

#[sqlx::test]
async fn valid_otp_returns_200_with_tokens_and_sets_email_verified(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "alice@test.edu", false).await;

    // Confirm the user starts unverified.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "user must start with email_verified = false"
    );

    let state = test_state(pool.clone());
    let otp_code = generate_otp(&pool, user_id, "email_verify").await;

    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["verified"], true);

    // Tokens must be included so the user is immediately authenticated
    // without a redundant login.
    let access_token = json["access_token"].as_str().expect("access_token");
    assert!(!access_token.is_empty(), "access_token must not be empty");
    let refresh_token = json["refresh_token"].as_str().expect("refresh_token");
    assert_eq!(
        refresh_token.len(),
        64,
        "refresh_token must be 64 hex chars"
    );
    assert_eq!(json["expires_in"], 900);

    // Verify the DB was updated.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "email_verified must be true in DB after successful verification"
    );
}

// Verify that the issued access token is valid and can access /me.
#[sqlx::test]
async fn verify_email_issued_token_works_for_me_endpoint(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "alice@test.edu", false).await;

    let state = test_state(pool.clone());
    let otp_code = generate_otp(&pool, user_id, "email_verify").await;

    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let access_token = json["access_token"].as_str().unwrap();

    // Use the token to call /me — must return the user's profile.
    let me_app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/me",
        web::get().to(uni_stash_be::features::auth::handlers::me),
    ))
    .await;
    let me_req = test::TestRequest::get()
        .uri("/api/v1/auth/me")
        .insert_header(("Authorization", format!("Bearer {access_token}")))
        .to_request();
    let me_resp = test::call_service(&me_app, me_req).await;
    assert_eq!(me_resp.status(), 200);
    let me_json: serde_json::Value = test::read_body_json(me_resp).await;
    assert_eq!(me_json["email"], "alice@test.edu");
    assert_eq!(me_json["email_verified"], true);
}

// ===========================================================================
// AC 2 — Invalid OTP code → 400 bad_request
// ===========================================================================

#[sqlx::test]
async fn invalid_otp_code_returns_400(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "bob@test.edu", false).await;

    let state = test_state(pool.clone());
    let _otp_code = generate_otp(&pool, user_id, "email_verify").await;

    // Use a completely wrong code.
    let resp = call_verify_otp(&state, "000000", "email_verify").await;

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");

    // email_verified must still be false.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "email_verified must remain false after invalid OTP"
    );
}

// ===========================================================================
// AC 3 — Expired OTP → 400 bad_request
// ===========================================================================

#[sqlx::test]
async fn expired_otp_returns_400(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "carol@test.edu", false).await;

    // Generate a real OTP, then manually expire it by backdating expires_at.
    let otp_code = generate_otp(&pool, user_id, "email_verify").await;
    let code_hash = otp::hash_otp(&otp_code);

    sqlx::query!(
        "UPDATE otps SET expires_at = now() - interval '1 minute' WHERE code = $1",
        &code_hash,
    )
    .execute(&pool)
    .await
    .expect("expire the OTP");

    let state = test_state(pool.clone());
    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");
    assert!(
        json["error"]["message"]
            .as_str()
            .unwrap()
            .contains("expired"),
        "error message should mention OTP is expired"
    );

    // email_verified must still be false.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "email_verified must remain false after expired OTP"
    );
}

// ===========================================================================
// AC 4 — Re-verifying an already-verified user → 200, idempotent
// ===========================================================================

#[sqlx::test]
async fn already_verified_user_returns_200_idempotent(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "dave@test.edu", true).await;

    // Confirm the user is already verified.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "user must start with email_verified = true"
    );

    let state = test_state(pool.clone());
    let otp_code = generate_otp(&pool, user_id, "email_verify").await;

    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;

    assert_eq!(
        resp.status(),
        200,
        "re-verifying an already-verified user must be idempotent (200, not error)"
    );
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["verified"], true);

    // Still verified in DB.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "email_verified must remain true after idempotent re-verification"
    );
}

// ===========================================================================
// AC 5 — OTP consumed after use (single-use enforcement)
// ===========================================================================

#[sqlx::test]
async fn otp_is_single_use_reuse_returns_400(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "eve@test.edu", false).await;

    let state = test_state(pool.clone());
    let otp_code = generate_otp(&pool, user_id, "email_verify").await;

    // First use — should succeed.
    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;
    assert_eq!(resp.status(), 200);

    // Second use — must fail because the OTP is consumed.
    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;
    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");
    assert!(
        json["error"]["message"]
            .as_str()
            .unwrap()
            .contains("invalid"),
        "reused OTP should produce an invalid/expired error, got: {:?}",
        json["error"]["message"]
    );

    // But email_verified is still true from the first use.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "email_verified must remain true — first use was successful"
    );
}

// ===========================================================================
// Wrong OTP type is rejected
// ===========================================================================

#[sqlx::test]
async fn wrong_otp_type_is_rejected(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "frank@test.edu", false).await;

    let state = test_state(pool.clone());
    // Generate a password_reset OTP but try to use it for email_verify.
    let otp_code = generate_otp(&pool, user_id, "password_reset").await;

    let resp = call_verify_otp(&state, &otp_code, "email_verify").await;

    assert_eq!(resp.status(), 400);
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "email_verified must remain false when wrong OTP type is used"
    );
}

// ===========================================================================
// Malformed OTP format is rejected
// ===========================================================================

#[sqlx::test]
async fn malformed_otp_format_returns_400(pool: PgPool) {
    let state = test_state(pool);

    // Too short
    let resp = call_verify_otp(&state, "12345", "email_verify").await;
    assert_eq!(resp.status(), 400);

    // Contains letters
    let resp = call_verify_otp(&state, "12ab56", "email_verify").await;
    assert_eq!(resp.status(), 400);

    // Too long
    let resp = call_verify_otp(&state, "1234567", "email_verify").await;
    assert_eq!(resp.status(), 400);
}
