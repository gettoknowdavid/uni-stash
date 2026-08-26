// apps/api/tests/auth_refresh_cm_3_7.rs
//
// CM-3.7 — Refresh token rotation integration tests.
//
//   AC 1 — Valid refresh token → 200 with new access + refresh pair
//   AC 2 — Old token is revoked (revoked=true, revoked_at set) after rotation
//   AC 3 — Old token's superseded_by points to the new token
//   AC 4 — Expired refresh token → 401
//   AC 5 — Already-revoked token → 401 (reuse detection, CM-3.8 placeholder)
//   AC 6 — Unknown/fake token → 401
//   AC 7 — New refresh token is valid and distinct from the old one

use actix_web::{App, test, web};
use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::password;
use uni_stash_be::core::auth::refresh_token;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::auth::models::RefreshToken;
use uni_stash_be::features::auth::repo::AuthRepo;

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

async fn insert_user(
    pool: &PgPool,
    school_id: i16,
    email: &str,
    password: &str,
    email_verified: bool,
) -> Uuid {
    let hash = password::hash_password(password).expect("hash password");
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, $2, $3, 'Test User', $4)
         RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(&hash)
    .bind(email_verified)
    .fetch_one(pool)
    .await
    .expect("insert user")
}

/// Insert a refresh token row directly into the DB and return `(plain, row_id)`.
async fn insert_refresh_token(
    pool: &PgPool,
    user_id: Uuid,
    family_id: Uuid,
    revoked: bool,
) -> (String, Uuid) {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    let id = sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, revoked, expires_at)
         VALUES ($1, $2, $3, $4, now() + interval '21 days')
         RETURNING id",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(family_id)
    .bind(revoked)
    .fetch_one(pool)
    .await
    .expect("insert refresh token");
    (plain, id)
}

/// Insert an already-expired refresh token and return its plain value.
async fn insert_expired_refresh_token(pool: &PgPool, user_id: Uuid, family_id: Uuid) -> String {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, $3, now() - interval '1 day')",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(family_id)
    .execute(pool)
    .await
    .expect("insert expired refresh token");
    plain
}

async fn find_token_by_id(pool: &PgPool, token_id: Uuid) -> RefreshToken {
    sqlx::query_as!(
        RefreshToken,
        "SELECT * FROM refresh_tokens WHERE id = $1",
        token_id
    )
    .fetch_one(pool)
    .await
    .expect("find token")
}

async fn call_refresh(
    state: &web::Data<AppState>,
    refresh_token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/refresh",
        web::post().to(uni_stash_be::features::auth::handlers::refresh),
    ))
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/refresh")
        .set_json(serde_json::json!({ "refresh_token": refresh_token }))
        .to_request();

    test::call_service(&app, req).await
}

// ===========================================================================
// AC 1 — Valid refresh token → 200 with new access + refresh pair
// ===========================================================================

#[sqlx::test]
async fn valid_refresh_token_returns_200_with_new_pair(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "alice@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, _id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], "success");
    let data = json["data"].as_object().expect("data must be an object");

    let access_token = data["access_token"].as_str().expect("access_token");
    assert!(!access_token.is_empty());

    let new_refresh = data["refresh_token"].as_str().expect("refresh_token");
    assert_eq!(new_refresh.len(), 64);
    assert!(new_refresh.chars().all(|c| c.is_ascii_hexdigit()));

    assert_eq!(data["expires_in"], 900);

    // The new refresh token must be different from the old one.
    assert_ne!(new_refresh, plain, "new refresh token must differ from old");
}

// ===========================================================================
// AC 2 — Old token is revoked after rotation
// ===========================================================================

#[sqlx::test]
async fn old_token_is_revoked_after_rotation(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "bob@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, old_id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;
    assert_eq!(resp.status(), 200);

    let old_token = find_token_by_id(&pool, old_id).await;
    assert!(old_token.revoked, "old token must be revoked");
    assert!(old_token.revoked_at.is_some(), "revoked_at must be set");
}

// ===========================================================================
// AC 3 — Old token's superseded_by points to new token
// ===========================================================================

#[sqlx::test]
async fn old_token_superseded_by_points_to_new(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "carol@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, old_id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;
    assert_eq!(resp.status(), 200);

    let old_token = find_token_by_id(&pool, old_id).await;
    assert!(
        old_token.superseded_by.is_some(),
        "superseded_by must be set"
    );

    // The new token must exist and be in the same family.
    let new_id = old_token.superseded_by.unwrap();
    let new_token = find_token_by_id(&pool, new_id).await;
    assert_eq!(
        new_token.family_id, family_id,
        "new token must be in same family"
    );
    assert_eq!(
        new_token.user_id, user_id,
        "new token must belong to same user"
    );
    assert!(!new_token.revoked, "new token must not be revoked");
}

// ===========================================================================
// AC 4 — Expired refresh token → 401
// ===========================================================================

#[sqlx::test]
async fn expired_refresh_token_returns_401(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "dave@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let plain = insert_expired_refresh_token(&pool, user_id, family_id).await;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// AC 5 — Already-revoked token → 401 (reuse detection)
// ===========================================================================

#[sqlx::test]
async fn revoked_refresh_token_returns_401_reuse_detected(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "eve@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, _id) = insert_refresh_token(&pool, user_id, family_id, true).await; // pre-revoked

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// AC 6 — Unknown/fake token → 401
// ===========================================================================

#[sqlx::test]
async fn unknown_refresh_token_returns_401(pool: PgPool) {
    let state = test_state(pool);
    let fake = refresh_token::generate_refresh_token_plain();

    let resp = call_refresh(&state, &fake).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// AC 7 — New refresh token is valid: can be used again (chain rotation)
// ===========================================================================

#[sqlx::test]
async fn new_refresh_token_can_be_rotated_again(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "frank@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, _old_id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let state = test_state(pool.clone());

    // First rotation.
    let resp1 = call_refresh(&state, &plain).await;
    assert_eq!(resp1.status(), 200);
    let json1: serde_json::Value = test::read_body_json(resp1).await;
    let second_plain = json1["data"]["refresh_token"].as_str().unwrap();

    // Second rotation with the new token.
    let resp2 = call_refresh(&state, second_plain).await;
    assert_eq!(resp2.status(), 200);
    let json2: serde_json::Value = test::read_body_json(resp2).await;
    let third_plain = json2["data"]["refresh_token"].as_str().unwrap();

    // All three tokens must be distinct.
    assert_ne!(plain, second_plain);
    assert_ne!(second_plain, third_plain);
    assert_ne!(plain, third_plain);
}

// ===========================================================================
// AC 8 — Rotation preserves same family_id
// ===========================================================================

#[sqlx::test]
async fn rotation_preserves_family_id(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "grace@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, _old_id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;
    assert_eq!(resp.status(), 200);

    // Verify all tokens in the DB for this user share the same family_id.
    let families: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT family_id FROM refresh_tokens WHERE user_id = $1")
            .bind(user_id)
            .fetch_all(&pool)
            .await
            .expect("query families");

    assert_eq!(families.len(), 1, "all tokens must share one family");
    assert_eq!(families[0], family_id);
}

// ===========================================================================
// AC 9 — End-to-end: fresh login → refresh
// ===========================================================================

#[sqlx::test]
async fn login_then_refresh_returns_new_pair_and_rotates(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let password_plain = "correct horse battery staple";
    let user_id = insert_user(&pool, school_id, "helen@test.edu", password_plain, true).await;

    let state = test_state(pool.clone());

    // Step 1: Call the login handler to get the initial refresh token.
    let login_app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/login",
        web::post().to(uni_stash_be::features::auth::handlers::login),
    ))
    .await;

    let login_req = test::TestRequest::post()
        .uri("/api/v1/auth/login")
        .set_json(serde_json::json!({
            "email": "helen@test.edu",
            "password": password_plain,
        }))
        .to_request();

    let login_resp = test::call_service(&login_app, login_req).await;
    assert_eq!(login_resp.status(), 200, "login must succeed");
    let login_json: serde_json::Value = test::read_body_json(login_resp).await;
    let login_data = login_json["data"].as_object().expect("login data");
    let issued_refresh = login_data["refresh_token"].as_str().expect("refresh_token");
    let issued_access = login_data["access_token"].as_str().expect("access_token");
    assert!(!issued_access.is_empty());
    assert_eq!(issued_refresh.len(), 64);

    // Find the refresh token row that login created.
    let auth_repo = AuthRepo::new(pool.clone());
    let issued_hash = refresh_token::hash_refresh_token(issued_refresh);
    let old_row = auth_repo
        .find_refresh_token_by_hash(&issued_hash)
        .await
        .expect("query")
        .expect("login must have inserted a refresh token row");
    let old_row_id = old_row.id;
    let family_id = old_row.family_id;

    // Step 2: Call the refresh handler with the login-issued token.
    let resp = call_refresh(&state, issued_refresh).await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;

    let refresh_data = json["data"].as_object().expect("refresh data");
    let new_refresh = refresh_data["refresh_token"].as_str().expect("new refresh_token");
    assert_ne!(
        new_refresh, issued_refresh,
        "new token must differ from old"
    );
    assert_eq!(refresh_data["expires_in"], 900);

    // Step 3: Verify old row is revoked and superseded_by points to new.
    let old_after = find_token_by_id(&pool, old_row_id).await;
    assert!(
        old_after.revoked,
        "old token must be revoked after rotation"
    );
    assert!(old_after.revoked_at.is_some(), "revoked_at must be set");
    let new_id = old_after.superseded_by.expect("superseded_by must be set");

    // Step 4: New row shares family_id and belongs to the same user.
    let new_row = find_token_by_id(&pool, new_id).await;
    assert_eq!(new_row.family_id, family_id, "family_id must be preserved");
    assert_eq!(new_row.user_id, user_id, "user_id must be preserved");
    assert!(!new_row.revoked, "new token must not be revoked");
}

// ===========================================================================
// AC 10 — New token expires_at is now() + TTL, not a hard cap
// ===========================================================================

#[sqlx::test]
async fn new_token_expires_at_is_now_plus_ttl(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(
        &pool,
        school_id,
        "ivan@test.edu",
        "correct horse battery staple",
        true,
    )
    .await;
    let family_id = Uuid::new_v4();
    let (plain, old_id) = insert_refresh_token(&pool, user_id, family_id, false).await;

    let old_row = find_token_by_id(&pool, old_id).await;
    let old_expires_at = old_row.expires_at;

    let state = test_state(pool.clone());
    let resp = call_refresh(&state, &plain).await;
    assert_eq!(resp.status(), 200);

    let old_after = find_token_by_id(&pool, old_id).await;
    let real_new_id = old_after.superseded_by.expect("superseded_by");
    let new_row = find_token_by_id(&pool, real_new_id).await;

    let now = time::OffsetDateTime::now_utc();
    let expected_min = now + time::Duration::days(20); // at least ~20 days from now
    let expected_max = now + time::Duration::days(22); // at most ~22 days from now

    assert!(
        new_row.expires_at >= expected_min,
        "new expires_at ({}) must be at least ~20 days from now",
        new_row.expires_at
    );
    assert!(
        new_row.expires_at <= expected_max,
        "new expires_at ({}) must be at most ~22 days from now",
        new_row.expires_at
    );

    // Crucially: the new window is relative to now, not inherited from the
    // old token's expiry. If old expires_at was far in the future (e.g. a
    // hard-cap model), the new one should NOT be equal to old_expires_at +
    // TTL_days — it should be roughly now + TTL_days.
    assert_ne!(
        new_row.expires_at, old_expires_at,
        "new expires_at must differ from old token's expires_at"
    );
}
