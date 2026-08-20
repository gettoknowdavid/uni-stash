// apps/api/tests/auth_verify_email_cm_3_5.rs
//
// CM-3.5 — Verify-email flow integration tests.
//
// Covers every acceptance criterion for the POST /api/v1/auth/verify-email endpoint:
//
//   AC 1 — Valid token → 200, email_verified flips to true in DB
//   AC 2 — Expired token → 401 with token_expired code
//   AC 3 — Wrong-purpose token (access token) → 401 unauthorized
//   AC 4 — Re-verifying an already-verified user → 200, idempotent, no error
//   AC 5 — Tampered token → 401

use actix_web::{App, test, web};
use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::jwt;
use uni_stash_be::core::auth::jwt::EmailVerifyClaims;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;

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

/// Encode arbitrary `EmailVerifyClaims` — allows crafting expired tokens.
fn encode_email_verify_claims(
    keys: &uni_stash_be::core::clients::JwtKeys,
    claims: &EmailVerifyClaims,
) -> String {
    jsonwebtoken::encode(
        &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256),
        claims,
        &keys.encoding,
    )
    .expect("encode test token")
}

fn make_email_verify_claims(user_id: Uuid, expired: bool) -> EmailVerifyClaims {
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    EmailVerifyClaims {
        sub: user_id,
        iat: now,
        exp: if expired { now - 3600 } else { now + 1800 },
        purpose: "email_verify".into(),
    }
}

/// POST /api/v1/auth/verify-email with the given token body.
async fn call_verify_email(
    state: &web::Data<AppState>,
    token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route(
                "/api/v1/auth/verify-email",
                web::post().to(uni_stash_be::features::auth::handlers::verify_email),
            ),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/verify-email")
        .set_json(serde_json::json!({ "token": token }))
        .to_request();

    test::call_service(&app, req).await
}

// ===========================================================================
// AC 1 — Valid token → 200, email_verified flips to true in DB
// ===========================================================================

#[sqlx::test]
async fn valid_token_returns_200_and_sets_email_verified(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "alice@test.edu", false).await;

    // Confirm the user starts unverified.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "user must start with email_verified = false"
    );

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool.clone(), &mock.uri());

    let claims = make_email_verify_claims(user_id, false);
    let token = encode_email_verify_claims(&state.jwt_keys, &claims);

    let resp = call_verify_email(&state, &token).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["email_verified"], true);

    // Verify the DB was updated.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "email_verified must be true in DB after successful verification"
    );
}

// ===========================================================================
// AC 2 — Expired token → 401 with token_expired code
// ===========================================================================

#[sqlx::test]
async fn expired_token_returns_401_with_token_expired_code(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "bob@test.edu", false).await;

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool.clone(), &mock.uri());

    let claims = make_email_verify_claims(user_id, true); // expired
    let token = encode_email_verify_claims(&state.jwt_keys, &claims);

    let resp = call_verify_email(&state, &token).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        json["error"]["code"], "token_expired",
        "expired token must produce the distinguishable token_expired code"
    );

    // email_verified must still be false.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "email_verified must remain false after expired token"
    );
}

// ===========================================================================
// AC 3 — Wrong-purpose token (access token) → 401 unauthorized
// ===========================================================================

#[sqlx::test]
async fn access_token_returns_401_unauthorized(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "carol@test.edu", false).await;

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool.clone(), &mock.uri());

    // Sign a valid access token — purpose is "access", not "email_verify".
    let access_token = jwt::sign_access_token(
        &state.jwt_keys,
        user_id,
        "carol@test.edu".into(),
        "Carol".into(),
        false,
    )
    .expect("sign access token");

    let resp = call_verify_email(&state, &access_token).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        json["error"]["code"], "unauthorized",
        "wrong-purpose token must be rejected with unauthorized"
    );
}

// ===========================================================================
// AC 4 — Re-verifying an already-verified user → 200, idempotent, no error
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

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool.clone(), &mock.uri());

    let claims = make_email_verify_claims(user_id, false);
    let token = encode_email_verify_claims(&state.jwt_keys, &claims);

    let resp = call_verify_email(&state, &token).await;

    assert_eq!(
        resp.status(),
        200,
        "re-verifying an already-verified user must be idempotent (200, not error)"
    );
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["email_verified"], true);

    // Still verified in DB.
    assert!(
        user_email_verified(&pool, &user_id).await,
        "email_verified must remain true after idempotent re-verification"
    );
}

// ===========================================================================
// AC 5 — Tampered token → 401
// ===========================================================================

#[sqlx::test]
async fn tampered_token_returns_401(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "eve@test.edu", false).await;

    let mock = wiremock::MockServer::start().await;
    let state = test_state(pool.clone(), &mock.uri());

    // Start with a valid token, then tamper with it.
    let claims = make_email_verify_claims(user_id, false);
    let token = encode_email_verify_claims(&state.jwt_keys, &claims);

    // Flip the last character to invalidate the signature.
    let mut chars: Vec<char> = token.chars().collect();
    if let Some(last) = chars.last_mut() {
        *last = match *last {
            'A' => 'B',
            _ => 'A',
        };
    }
    let tampered: String = chars.into_iter().collect();

    let resp = call_verify_email(&state, &tampered).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        json["error"]["code"], "unauthorized",
        "tampered token must be rejected with unauthorized (not token_expired)"
    );

    // email_verified must still be false.
    assert!(
        !user_email_verified(&pool, &user_id).await,
        "email_verified must remain false after tampered token"
    );
}
