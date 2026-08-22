// apps/api/tests/listings_search_cm_5_1.rs
//
// CM-5.1 — GET /listings?q=... ranked search integration tests.
//
// Acceptance Criteria:
//   AC 1 — `q` triggers plainto_tsquery('english', ...) against search_vector
//   AC 2 — Results ordered by ts_rank DESC (relevance, not recency)
//   AC 3 — Empty/whitespace-only `q` falls back to non-search browse
//   AC 4 — Search works in combination with category/price filters
//   AC 5 — Search uses limit (no cursor pagination for ranked results)

use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::listings::handlers::list_listings;

const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

fn test_config() -> Config {
    Config {
        database_url: "postgres://localhost:5432/uni_stash".into(),
        jwt_private_key: TEST_PRIVATE_PEM.into(),
        jwt_public_key: TEST_PUBLIC_PEM.into(),
        resend_api_key: "".into(),
        resend_base_url: "http://127.0.0.1:1".into(),
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
    let db = Db { pool };
    web::Data::new(AppState::new(&test_config(), db).expect("AppState"))
}

async fn seed_school(pool: &PgPool) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', 'test.edu') RETURNING id",
    )
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn seed_user(pool: &PgPool, school_id: i16, email: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name)
         VALUES ($1, $2, 'hash', 'Test User') RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .fetch_one(pool)
    .await
    .expect("seed user")
}

async fn seed_category(pool: &PgPool, slug: &str) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ($1, $1) RETURNING id",
    )
    .bind(slug)
    .fetch_one(pool)
    .await
    .expect("seed category")
}

/// Seed a listing with explicit title and description — the search trigger
/// will populate search_vector automatically via the BEFORE INSERT trigger.
async fn seed_listing_with_text(
    pool: &PgPool,
    seller_id: uuid::Uuid,
    category_id: i16,
    title: &str,
    description: &str,
    price: Option<i32>,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, price, condition, status)
         VALUES ($1, $2, $3, $4, $5, 'used', 'active') RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .bind(title)
    .bind(description)
    .bind(price)
    .fetch_one(pool)
    .await
    .expect("seed listing")
}

async fn call_search(state: &web::Data<AppState>, query: &str) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/listings", web::get().to(list_listings)),
    )
    .await;

    let uri = format!("/api/v1/listings{query}");
    let req = test::TestRequest::get().uri(&uri).to_request();
    test::call_service(&app, req).await
}

// ===========================================================================
// AC 1 — Search finds listings by term in title or description
// ===========================================================================

#[sqlx::test]
async fn search_finds_listings_by_title_term(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Organic Chemistry",
        "A comprehensive textbook",
        Some(45),
    )
    .await;
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Calculus I",
        "Intro to calculus",
        Some(30),
    )
    .await;

    let state = test_state(pool);
    let resp = call_search(&state, "?q=chemistry").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 1, "should find only the chemistry listing");
    assert_eq!(listings[0]["title"], "Organic Chemistry");
}

#[sqlx::test]
async fn search_finds_listings_by_description_term(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "electronics").await;

    // "laptop" only appears in the description, not the title
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Portable Computer",
        "A powerful laptop for students",
        Some(500),
    )
    .await;
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Desktop PC",
        "A powerful desktop for students",
        Some(300),
    )
    .await;

    let state = test_state(pool);
    let resp = call_search(&state, "?q=laptop").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        1,
        "should find only the listing mentioning laptop in description"
    );
    assert_eq!(listings[0]["title"], "Portable Computer");
}

// ===========================================================================
// AC 2 — Results ordered by ts_rank DESC (relevance, not recency)
// ===========================================================================

#[sqlx::test]
async fn search_results_ordered_by_relevance(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    // "physics" only in description — lower weight
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "General Science",
        "Covers physics and chemistry topics",
        Some(40),
    )
    .await;
    // "physics" in title — higher weight (A vs B)
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Physics 101",
        "Introduction to physics concepts",
        Some(35),
    )
    .await;

    let state = test_state(pool);
    let resp = call_search(&state, "?q=physics").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 2);
    // Title match (weight A) should rank above description-only match (weight B)
    assert_eq!(
        listings[0]["title"], "Physics 101",
        "title match must rank higher than description-only match"
    );
    assert_eq!(listings[1]["title"], "General Science");
}

// ===========================================================================
// AC 3 — Empty/whitespace-only q falls back to non-search browse
// ===========================================================================

#[sqlx::test]
async fn empty_q_falls_back_to_browse(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    seed_listing_with_text(&pool, seller, cat, "Item A", "", Some(10)).await;
    seed_listing_with_text(&pool, seller, cat, "Item B", "", Some(20)).await;

    let state = test_state(pool);

    // Empty q — should behave like normal browse (all active, recency order)
    let resp = call_search(&state, "?q=").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        2,
        "empty q should return all active listings"
    );

    // Whitespace-only q — same behavior
    let resp = call_search(&state, "?q=%20%20%20").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        2,
        "whitespace-only q should return all active listings"
    );
}

// ===========================================================================
// AC 4 — Search works in combination with category/price filters
// ===========================================================================

#[sqlx::test]
async fn search_respects_category_filter(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat_books = seed_category(&pool, "textbooks").await;
    let cat_elec = seed_category(&pool, "electronics").await;

    seed_listing_with_text(
        &pool,
        seller,
        cat_books,
        "Physics Textbook",
        "A great physics book",
        Some(45),
    )
    .await;
    seed_listing_with_text(
        &pool,
        seller,
        cat_elec,
        "Physics Simulator",
        "A physics simulation device",
        Some(200),
    )
    .await;

    let state = test_state(pool);

    // Search "physics" but only in textbooks category
    let resp = call_search(&state, &format!("?q=physics&category={cat_books}")).await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        1,
        "category filter must narrow search results"
    );
    assert_eq!(listings[0]["title"], "Physics Textbook");
}

#[sqlx::test]
async fn search_respects_price_filter(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Cheap Calculator",
        "A basic calculator",
        Some(10),
    )
    .await;
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Fancy Calculator",
        "A scientific calculator",
        Some(100),
    )
    .await;

    let state = test_state(pool);

    // Search "calculator" with max_price=50
    let resp = call_search(&state, "?q=calculator&max_price=50").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 1, "price filter must narrow search results");
    assert_eq!(listings[0]["title"], "Cheap Calculator");
}

// ===========================================================================
// AC 5 — Search uses limit, no cursor pagination
// ===========================================================================

#[sqlx::test]
async fn search_uses_limit_without_cursor(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    for i in 0..10 {
        seed_listing_with_text(
            &pool,
            seller,
            cat,
            &format!("Science Item {i}"),
            "A scientific item for students",
            Some(i * 10),
        )
        .await;
    }

    let state = test_state(pool);
    let resp = call_search(&state, "?q=science&limit=5").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 5, "must respect limit parameter");
    assert!(
        json["next_cursor"].is_null(),
        "search results must not return a cursor (no cursor-based pagination for rank ordering)"
    );
}

// ===========================================================================
// No match returns empty array
// ===========================================================================

#[sqlx::test]
async fn search_returns_empty_for_no_match(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    seed_listing_with_text(&pool, seller, cat, "Laptop", "A computer", Some(500)).await;

    let state = test_state(pool);
    let resp = call_search(&state, "?q=banana").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        0,
        "non-matching search must return empty array"
    );
    assert!(json["next_cursor"].is_null());
}
