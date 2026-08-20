// apps/api/tests/middleware_cm_3_3.rs
//
// CM-3.3 integration test: boots a real Actix `App` with a protected route
// that takes `AuthUser` as an extractor, then verifies every AC:
//
//   AC 2 — Missing/ malformed Authorization header → 401
//   AC 3 — Expired token → 401 with a distinguishable error code
//   AC 4 — Valid token → 200 with typed user info (no re-parsing needed)
//   AC 5 — Wrong-purpose token rejected (email_verify ≠ access)

use actix_web::{App, http::header, test, web};
use jsonwebtoken::Header;
use uni_stash_be::core::clients::JwtKeys;
use uuid::Uuid;

use uni_stash_be::core::auth::jwt::{self, AccessClaims};
use uni_stash_be::core::auth::middleware::AuthUser;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::{AppState};

// ---------------------------------------------------------------------------
// Test fixtures — the same 2048-bit RSA keypair used by CM-3.2 unit tests.
// ---------------------------------------------------------------------------

const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

fn test_state() -> web::Data<AppState> {
    // The middleware only reads `jwt_keys`; we use a lazy pool so no real
    // Postgres connection is opened during the test.
    let config = Config {
        database_url: "postgres://localhost:5432/uni_stash".into(),
        jwt_private_key: TEST_PRIVATE_PEM.into(),
        jwt_public_key: TEST_PUBLIC_PEM.into(),
        resend_api_key: "test".into(),
        resend_base_url: "https://api.resend.com".into(),
        port: 8080,
        env: "test".into(),
        r2_bucket: "test".into(),
        r2_access_key_id: "test".into(),
        r2_secret_access_key: "test".into(),
        r2_endpoint: "https://test.r2.cloudflarestorage.com".into(),
        frontend_base_url: "https://uni-stash.com".into(),
    };
    let db = Db {
        pool: sqlx::postgres::PgPoolOptions::new()
            .connect_lazy(&config.database_url)
            .expect("connect_lazy"),
    };
    web::Data::new(AppState::new(&config, db).expect("AppState"))
}

// ---------------------------------------------------------------------------
// Protected handler — mirrors a typical profile endpoint that takes AuthUser.
// ---------------------------------------------------------------------------

async fn protected_handler(user: AuthUser) -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok().json(serde_json::json!({
        "user_id": user.id,
        "email": user.email,
        "email_verified": user.email_verified,
        "display_name": user.display_name,
    }))
}

// ---------------------------------------------------------------------------
// Helper: encode an `AccessClaims` directly (bypasses sign_access_token so
// we can craft expired / wrong-purpose tokens).
// ---------------------------------------------------------------------------

fn encode_claims(keys: &JwtKeys, claims: &AccessClaims) -> String {
    jsonwebtoken::encode(
        &Header::new(jsonwebtoken::Algorithm::RS256),
        claims,
        &keys.encoding,
    )
    .expect("encode test token")
}

// ===========================================================================
// Tests
// ===========================================================================

/// AC 2 — Missing `Authorization` header → 401 with code `"unauthorized"`.
#[actix_web::test]
async fn missing_header_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state)
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let req = test::TestRequest::get().uri("/protected").to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["error"]["code"], "unauthorized");
}

/// AC 2 — `Authorization` header without `Bearer ` prefix → 401.
#[actix_web::test]
async fn non_bearer_scheme_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state)
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, "Basic dXNlcjpwYXNz"))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["error"]["code"], "unauthorized");
}

/// AC 2 — Empty bearer token → 401.
#[actix_web::test]
async fn empty_bearer_token_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state)
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, "Bearer "))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["error"]["code"], "unauthorized");
}

/// AC 2 — Gibberish token → 401.
#[actix_web::test]
async fn gibberish_token_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state)
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, "Bearer not-a-real-jwt"))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["error"]["code"], "unauthorized");
}

/// AC 3 — Expired token → 401 with the distinguishable `"token_expired"` code
/// (not the same `"unauthorized"` code used for missing/invalid tokens, so the
/// client can trigger an automatic refresh flow).
#[actix_web::test]
async fn expired_token_returns_401_with_token_expired_code() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let user_id = Uuid::new_v4();
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    let claims = AccessClaims {
        sub: user_id,
        iat: now - 7200,
        exp: now - 3600, // expired an hour ago
        purpose: "access".into(),
        email: "expired@campus.edu".into(),
        display_name: "Expired User".into(),
        email_verified: false,
    };
    let token = encode_claims(&state.jwt_keys, &claims);

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        body["error"]["code"], "token_expired",
        "expired token must produce the distinguishable token_expired code"
    );
}

/// AC 3 — Tampered signature → 401 with generic `"unauthorized"` code (NOT
/// `token_expired` — the signature check fails before the expiry check).
#[actix_web::test]
async fn tampered_signature_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let user_id = Uuid::new_v4();
    let token = jwt::sign_access_token(
        &state.jwt_keys,
        user_id,
        "valid@campus.edu".into(),
        "Valid User".into(),
        true,
    )
    .unwrap();

    // Flip the last character to invalidate the signature.
    let mut chars: Vec<char> = token.chars().collect();
    if let Some(last) = chars.last_mut() {
        *last = match *last {
            'A' => 'B',
            _ => 'A',
        };
    }
    let tampered: String = chars.into_iter().collect();

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, format!("Bearer {tampered}")))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        body["error"]["code"], "unauthorized",
        "tampered token must be rejected with unauthorized, not token_expired"
    );
}

/// AC 4 — Token with `purpose: "email_verify"` → 401 (the middleware calls
/// `verify_access_token` which rejects non-`"access"` purpose).
#[actix_web::test]
async fn email_verify_purpose_token_returns_401() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let user_id = Uuid::new_v4();
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    let claims = AccessClaims {
        sub: user_id,
        iat: now,
        exp: now + 1800,
        purpose: "email_verify".into(),
        email: "verify@campus.edu".into(),
        display_name: "Verify User".into(),
        email_verified: false,
    };
    let token = encode_claims(&state.jwt_keys, &claims);

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["error"]["code"], "unauthorized");
}

/// AC 4 — Valid access token → 200 with the user's typed info returned by the
/// `AuthUser` extractor, proving the handler never re-parses the token.
#[actix_web::test]
async fn valid_token_returns_200_with_user_info() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let user_id = Uuid::new_v4();
    let token = jwt::sign_access_token(
        &state.jwt_keys,
        user_id,
        "alice@campus.edu".into(),
        "Alice Adebayo".into(),
        true,
    )
    .unwrap();

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["user_id"], user_id.to_string());
    assert_eq!(body["email"], "alice@campus.edu");
    assert_eq!(body["display_name"], "Alice Adebayo");
    assert_eq!(body["email_verified"], true);
}

/// Separate `email_verified = false` claim round-trips correctly — the
/// extractor preserves the boolean faithfully, which the signup / login
/// flows depend on.
#[actix_web::test]
async fn unverified_email_round_trips_through_extractor() {
    let state = test_state();
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/protected", web::get().to(protected_handler)),
    )
    .await;

    let user_id = Uuid::new_v4();
    let token = jwt::sign_access_token(
        &state.jwt_keys,
        user_id,
        "bob@campus.edu".into(),
        "Bob B".into(),
        false, // email not yet verified
    )
    .unwrap();

    let req = test::TestRequest::get()
        .uri("/protected")
        .insert_header((header::AUTHORIZATION, format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["email_verified"], false);
}
