// apps/api/tests/listings_create_cm_4_1.rs
//
// CM-4.1 — POST /listings integration tests.
//
// Covers every acceptance criterion for the listing creation endpoint:
//
//   AC 1 — 401 without auth token
//   AC 2 — 403 when email_verified = false
//   AC 3 — 422 on validation failure (empty title, negative price)
//   AC 4 — 400 on FK violation (nonexistent category)
//   AC 5 — 201 on happy path with full response body
//   AC 6 — seller_id derived from token, not trusted from body
//   AC 7 — 201 on barter-only (null price)
//   AC 8 — 201 on omitted description (defaults to empty string)

use actix_web::{App, ResponseError, test, web};
use sqlx::PgPool;
use uni_stash_be::core::auth::jwt;
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
        resend_api_key: "re_test_key".into(),
        resend_base_url: "http://127.0.0.1:1".into(), // unused for listing tests
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

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

async fn seed_school(pool: &PgPool, domain: &str) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', $1) RETURNING id",
    )
    .bind(domain)
    .fetch_one(pool)
    .await
    .expect("seed school")
}

/// Insert a user directly into the DB with the given email_verified flag.
/// Returns the user's UUID.
async fn seed_verified_user(
    pool: &PgPool,
    school_id: i16,
    email: &str,
    email_verified: bool,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, $2, 'dummy_hash', 'Test User', $3)
         RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(email_verified)
    .fetch_one(pool)
    .await
    .expect("seed user")
}

/// Insert a category and return its id.
async fn seed_category(pool: &PgPool, slug: &str, label: &str) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ($1, $2) RETURNING id",
    )
    .bind(slug)
    .bind(label)
    .fetch_one(pool)
    .await
    .expect("seed category")
}

/// Build a JWT access token for the given user, matching the shape the
/// auth middleware expects.
fn sign_access_token(
    keys: &uni_stash_be::core::clients::JwtKeys,
    user_id: uuid::Uuid,
    email: &str,
    email_verified: bool,
) -> String {
    let user = uni_stash_be::features::auth::models::User {
        id: user_id,
        school_id: 1,
        email: email.to_string(),
        display_name: "Test User".to_string(),
        email_verified,
        role: "student".to_string(),
        created_at: time::OffsetDateTime::now_utc(),
        updated_at: time::OffsetDateTime::now_utc(),
        password_hash: String::new(),
    };
    jwt::sign_access_token(keys, &user).expect("sign access token")
}

// ---------------------------------------------------------------------------
// Request helpers
// ---------------------------------------------------------------------------

fn listing_body(title: &str, category_id: i16) -> serde_json::Value {
    serde_json::json!({
        "title": title,
        "description": "A test listing",
        "category_id": category_id,
        "price": 100,
        "condition": "new",
    })
}

fn full_listing_body(
    title: &str,
    category_id: i16,
    price: Option<i32>,
    condition: &str,
) -> serde_json::Value {
    let mut body = serde_json::json!({
        "title": title,
        "category_id": category_id,
        "condition": condition,
    });
    if let Some(p) = price {
        body["price"] = serde_json::json!(p);
    }
    body
}

async fn call_create_listing(
    state: &web::Data<AppState>,
    body: &serde_json::Value,
    auth_header: Option<&str>,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/listings",
        web::post().to(uni_stash_be::features::listings::handlers::create_listing),
    ))
    .await;

    let mut builder = test::TestRequest::post()
        .uri("/api/v1/listings")
        .set_json(body);

    if let Some(token) = auth_header {
        builder = builder.insert_header(("Authorization", format!("Bearer {token}")));
    }

    let req = builder.to_request();
    test::call_service(&app, req).await
}

/// Count rows in the listings table.
async fn listing_count(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM listings")
        .fetch_one(pool)
        .await
        .expect("count listings")
}

// ===========================================================================
// AC 1 — No Authorization header → 401
// ===========================================================================

#[sqlx::test]
async fn create_listing_requires_auth(pool: PgPool) {
    let state = test_state(pool);
    let body = listing_body("Test", 1);
    let resp = call_create_listing(&state, &body, None).await;

    assert_eq!(resp.status(), 401);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// AC 2 — email_verified = false → 403
// ===========================================================================

#[sqlx::test]
async fn create_listing_requires_email_verified(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", false).await;
    let category_id = seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(pool);
    let keys = &state.jwt_keys;
    let token = sign_access_token(keys, user_id, "alice@test.edu", false);

    let body = listing_body("My Book", category_id);
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 403);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "email_not_verified");
}

// ===========================================================================
// AC 3 — Validation: empty title → 422, negative price → 422
// ===========================================================================

#[actix_web::test]
async fn create_listing_validates_title_before_db_call() {
    use uni_stash_be::features::listings::dtos::CreateListingRequest;
    use uni_stash_be::features::listings::models;
    use validator::Validate;

    // Empty title fails validation
    let req = CreateListingRequest {
        title: "".into(),
        description: None,
        category_id: 1,
        price: None,
        condition: models::Condition::New,
    };
    let err = req.validate().unwrap_err();
    let app_err: uni_stash_be::core::error::AppError = err.into();
    assert_eq!(app_err.status_code(), 422);
    assert_eq!(app_err.code(), "validation");
}

#[actix_web::test]
async fn create_listing_rejects_negative_price() {
    use uni_stash_be::features::listings::dtos::CreateListingRequest;
    use uni_stash_be::features::listings::models;
    use validator::Validate;

    let req = CreateListingRequest {
        title: "Laptop".into(),
        description: Some("Used".into()),
        category_id: 1,
        price: Some(-100),
        condition: models::Condition::Used,
    };
    let err = req.validate().unwrap_err();
    let app_err: uni_stash_be::core::error::AppError = err.into();
    assert_eq!(app_err.status_code(), 422);
    assert_eq!(app_err.code(), "validation");
}

/// Verify validation prevents DB insertion (no row inserted when title is empty).
#[sqlx::test]
async fn empty_title_does_not_insert_row(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;
    let category_id = seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(pool.clone());
    let token = sign_access_token(&state.jwt_keys, user_id, "alice@test.edu", true);

    // Send empty title — validation should fail before DB
    let body = serde_json::json!({
        "title": "",
        "category_id": category_id,
        "price": 100,
        "condition": "new",
    });
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 422);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "validation");

    // Prove no row was inserted
    assert_eq!(
        listing_count(&pool).await,
        0,
        "validation failure must not insert a row"
    );
}

// ===========================================================================
// AC 4 — FK violation: nonexistent category → 400
// ===========================================================================

#[sqlx::test]
async fn create_listing_rejects_nonexistent_category(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;

    let state = test_state(pool);
    let token = sign_access_token(&state.jwt_keys, user_id, "alice@test.edu", true);

    // category_id 9999 does not exist → FK violation
    let body = listing_body("My Book", 9999);
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");
}

// ===========================================================================
// AC 5 — Happy path: 201 with full object
// ===========================================================================

#[sqlx::test]
async fn create_listing_success_returns_201_with_full_object(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;
    let category_id = seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(pool);
    let token = sign_access_token(&state.jwt_keys, user_id, "alice@test.edu", true);

    let body = full_listing_body("Organic Chemistry 8th Ed", category_id, Some(45), "used");
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;

    // Full object returned
    assert!(json["id"].is_string(), "must include a UUID id");
    assert_eq!(json["seller_id"], user_id.to_string());
    assert_eq!(json["category_id"], category_id);
    assert_eq!(json["title"], "Organic Chemistry 8th Ed");
    assert_eq!(json["price"], 45);
    assert_eq!(json["condition"], "used");
    assert_eq!(json["status"], "active");
    assert!(
        json["reserved_by"].is_null(),
        "reserved_by must be null for a fresh listing"
    );
    assert!(
        json["reserved_at"].is_null(),
        "reserved_at must be null for a fresh listing"
    );
}

// ===========================================================================
// AC 6 — seller_id is never trusted from the request body
// ===========================================================================

#[sqlx::test]
async fn create_listing_seller_id_is_never_trusted_from_body(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let real_user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;
    let other_user_id = seed_verified_user(&pool, school_id, "bob@test.edu", true).await;
    let category_id = seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(pool);
    let token = sign_access_token(&state.jwt_keys, real_user_id, "alice@test.edu", true);

    // Send a body that includes an unrelated seller_id field — it should be
    // ignored by serde (extra fields are ignored by default in actix's Json)
    let body = serde_json::json!({
        "title": "Hacked Listing",
        "seller_id": other_user_id.to_string(),
        "category_id": category_id,
        "price": 100,
        "condition": "new",
    });
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;

    // The seller_id must be the authenticated user, not the one from the body
    assert_eq!(
        json["seller_id"],
        real_user_id.to_string(),
        "seller_id must come from the JWT, not the request body"
    );
    assert_ne!(
        json["seller_id"],
        other_user_id.to_string(),
        "seller_id must never be the attacker-supplied value"
    );
}

// ===========================================================================
// AC 7 — Barter-only: omit price → 201, price is null
// ===========================================================================

#[sqlx::test]
async fn create_listing_barter_only_allows_null_price(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;
    let category_id = seed_category(&pool, "furniture", "Furniture").await;

    let state = test_state(pool);
    let token = sign_access_token(&state.jwt_keys, user_id, "alice@test.edu", true);

    let body = full_listing_body("Free Couch", category_id, None, "fair");
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;

    assert!(
        json["price"].is_null(),
        "barter-only listing must have null price"
    );
    assert_eq!(json["title"], "Free Couch");
    assert_eq!(json["condition"], "fair");
}

// ===========================================================================
// AC 8 — Default description when omitted → 201, description is ""
// ===========================================================================

#[sqlx::test]
async fn create_listing_default_description_when_omitted(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = seed_verified_user(&pool, school_id, "alice@test.edu", true).await;
    let category_id = seed_category(&pool, "electronics", "Electronics").await;

    let state = test_state(pool);
    let token = sign_access_token(&state.jwt_keys, user_id, "alice@test.edu", true);

    // Send a body WITHOUT description
    let body = serde_json::json!({
        "title": "USB Cable",
        "category_id": category_id,
        "price": 5,
        "condition": "new",
    });
    let resp = call_create_listing(&state, &body, Some(&token)).await;

    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;

    assert_eq!(
        json["description"].as_str(),
        Some(""),
        "omitted description must default to empty string (matches DB DEFAULT '')"
    );
}
