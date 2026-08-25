// apps/api/tests/auth_logout_me_cm_3_9.rs
//
// CM-3.9 — POST /auth/logout & GET /auth/me integration tests.
//
//   Logout ACs:
//   1. Valid refresh token → 200, row's revoked flips to true
//   2. Unknown token → 200 (idempotent)
//   3. Already-revoked token → 200 (idempotent)
//
//   Me ACs:
//   4. Valid access token → 200, correct profile fields including role
//   5. No token → 401 (via CM-3.3's existing extractor)

use actix_web::{App, test, web};
use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::jwt;
use uni_stash_be::core::auth::password;
use uni_stash_be::core::auth::refresh_token;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::auth::models::{RefreshToken, User};

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

async fn insert_user(pool: &PgPool, school_id: i16, email: &str, email_verified: bool) -> User {
    let hash = password::hash_password("correct horse battery staple").expect("hash password");
    sqlx::query_as::<_, User>(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified, role)
         VALUES ($1, $2, $3, 'Test User', $4, 'student')
         RETURNING *",
    )
    .bind(school_id)
    .bind(email)
    .bind(&hash)
    .bind(email_verified)
    .fetch_one(pool)
    .await
    .expect("insert user")
}

/// Insert a refresh token row and return `(plain, row_id)`.
async fn insert_refresh_token(pool: &PgPool, user_id: Uuid, family_id: Uuid) -> (String, Uuid) {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    let id = sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, $3, now() + interval '21 days')
         RETURNING id",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(family_id)
    .fetch_one(pool)
    .await
    .expect("insert refresh token");
    (plain, id)
}

async fn find_token_by_hash(pool: &PgPool, plain: &str) -> RefreshToken {
    let hash = refresh_token::hash_refresh_token(plain);
    sqlx::query_as::<_, RefreshToken>("SELECT * FROM refresh_tokens WHERE token_hash = $1")
        .bind(&hash)
        .fetch_one(pool)
        .await
        .expect("find token by hash")
}

async fn call_logout(
    state: &web::Data<AppState>,
    refresh_token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/logout",
        web::post().to(uni_stash_be::features::auth::handlers::logout),
    ))
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/logout")
        .set_json(serde_json::json!({ "refresh_token": refresh_token }))
        .to_request();

    test::call_service(&app, req).await
}

async fn call_me(
    state: &web::Data<AppState>,
    access_token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/me",
        web::get().to(uni_stash_be::features::auth::handlers::me),
    ))
    .await;

    let req = test::TestRequest::get()
        .uri("/api/v1/auth/me")
        .insert_header(("Authorization", format!("Bearer {access_token}")))
        .to_request();

    test::call_service(&app, req).await
}

// ===========================================================================
// Logout AC 1 — Valid refresh token → 200, row revoked
// ===========================================================================

#[sqlx::test]
async fn logout_valid_token_returns_200_and_revokes(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user = insert_user(&pool, school_id, "alice@test.edu", true).await;
    let family_id = Uuid::new_v4();
    let (plain, _id) = insert_refresh_token(&pool, user.id, family_id).await;

    let state = test_state(pool.clone());
    let resp = call_logout(&state, &plain).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], "ok");

    // Verify the row is now revoked in the DB.
    let row = find_token_by_hash(&pool, &plain).await;
    assert!(row.revoked, "token must be revoked after logout");
    assert!(row.revoked_at.is_some(), "revoked_at must be set");
}

// ===========================================================================
// Logout AC 2 — Unknown token → 200 (idempotent)
// ===========================================================================

#[sqlx::test]
async fn logout_unknown_token_returns_200_idempotent(pool: PgPool) {
    let state = test_state(pool);
    let fake = refresh_token::generate_refresh_token_plain();

    let resp = call_logout(&state, &fake).await;

    assert_eq!(resp.status(), 200, "unknown token must not error");
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], "ok");
}

// ===========================================================================
// Logout AC 3 — Already-revoked token → 200 (idempotent)
// ===========================================================================

#[sqlx::test]
async fn logout_already_revoked_token_returns_200_idempotent(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user = insert_user(&pool, school_id, "bob@test.edu", true).await;
    let family_id = Uuid::new_v4();
    let (plain, _id) = insert_refresh_token(&pool, user.id, family_id).await;

    let state = test_state(pool.clone());

    // First logout — revokes the token.
    let resp1 = call_logout(&state, &plain).await;
    assert_eq!(resp1.status(), 200);

    // Second logout — already revoked, must still return 200.
    let resp2 = call_logout(&state, &plain).await;
    assert_eq!(resp2.status(), 200, "re-logout must be idempotent");
    let json: serde_json::Value = test::read_body_json(resp2).await;
    assert_eq!(json["status"], "ok");
}

// ===========================================================================
// Me AC 4 — Valid access token → 200, correct profile fields including role
// ===========================================================================

#[sqlx::test]
async fn me_valid_token_returns_200_with_profile(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user = insert_user(&pool, school_id, "carol@test.edu", true).await;

    let state = test_state(pool.clone());

    // Sign an access token for this user.
    let access_token = jwt::sign_access_token(&state.jwt_keys, &user).expect("sign access token");

    let resp = call_me(&state, &access_token).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;

    assert_eq!(json["id"], user.id.to_string());
    assert_eq!(json["email"], "carol@test.edu");
    assert_eq!(json["display_name"], "Test User");
    assert_eq!(json["email_verified"], true);
    assert_eq!(json["role"], "student");
}

// ===========================================================================
// Me AC 5 — No token → 401
// ===========================================================================

#[sqlx::test]
async fn me_no_token_returns_401(pool: PgPool) {
    let state = test_state(pool);

    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/me",
        web::get().to(uni_stash_be::features::auth::handlers::me),
    ))
    .await;

    // No Authorization header at all.
    let req = test::TestRequest::get().uri("/api/v1/auth/me").to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401, "missing token must return 401");
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// Me — role is fetched from DB, not from JWT
// ===========================================================================

#[sqlx::test]
async fn me_role_reflects_db_not_jwt(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user = insert_user(&pool, school_id, "dave@test.edu", true).await;

    // Sign an access token — at this point the JWT carries role="student"
    // (from the User struct used at signing time).
    let state = test_state(pool.clone());
    let access_token = jwt::sign_access_token(&state.jwt_keys, &user).expect("sign access token");

    // Now update the user's role in the DB to "admin".
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(user.id)
        .execute(&pool)
        .await
        .expect("update role");

    // The /me endpoint should return "admin" from the DB, NOT "student"
    // from the stale JWT claims — proving role is re-queried.
    let resp = call_me(&state, &access_token).await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["role"], "admin", "role must come from DB, not JWT");
}
