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

async fn seed_listing(
    pool: &PgPool,
    seller_id: uuid::Uuid,
    category_id: i16,
    title: &str,
    price: Option<i32>,
    condition: &str,
    status: &str,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, price, condition, status)
         VALUES ($1, $2, $3, '', $4, $5, $6) RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .bind(title)
    .bind(price)
    .bind(condition)
    .bind(status)
    .fetch_one(pool)
    .await
    .expect("seed listing")
}

async fn call_browse(state: &web::Data<AppState>, query: &str) -> actix_web::dev::ServiceResponse {
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
// Default: active status filter, limit 20
// ===========================================================================

#[sqlx::test]
async fn default_limit_and_status_filter_applied(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    seed_listing(&pool, seller, cat, "Active 1", Some(10), "new", "active").await;
    seed_listing(&pool, seller, cat, "Active 2", Some(20), "used", "active").await;
    seed_listing(&pool, seller, cat, "Active 3", Some(30), "fair", "active").await;
    seed_listing(&pool, seller, cat, "Sold Item", Some(50), "new", "sold").await;

    let state = test_state(pool);
    let resp = call_browse(&state, "").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 3, "sold listing must be excluded");
    assert!(json["next_cursor"].is_null());
}

// ===========================================================================
// Category filter narrows results
// ===========================================================================

#[sqlx::test]
async fn category_filter_narrows_results(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat_a = seed_category(&pool, "textbooks").await;
    let cat_b = seed_category(&pool, "electronics").await;

    seed_listing(&pool, seller, cat_a, "Book", Some(10), "new", "active").await;
    seed_listing(&pool, seller, cat_b, "Laptop", Some(200), "used", "active").await;

    let state = test_state(pool);
    let resp = call_browse(&state, &format!("?category={cat_a}")).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 1);
    assert_eq!(listings[0]["title"], "Book");
}

// ===========================================================================
// Min/max price filters narrow results
// ===========================================================================

#[sqlx::test]
async fn min_max_price_filter_narrows_results(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    seed_listing(&pool, seller, cat, "Cheap", Some(10), "used", "active").await;
    seed_listing(&pool, seller, cat, "Mid", Some(50), "used", "active").await;
    seed_listing(&pool, seller, cat, "Expensive", Some(200), "new", "active").await;

    let state = test_state(pool);
    let resp = call_browse(&state, "?min_price=20&max_price=100").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 1);
    assert_eq!(listings[0]["title"], "Mid");
}

// ===========================================================================
// Pagination returns next_cursor when more rows exist
// ===========================================================================

#[sqlx::test]
async fn pagination_returns_next_cursor_when_more_rows_exist(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    for i in 0..25 {
        seed_listing(
            &pool,
            seller,
            cat,
            &format!("Item {i}"),
            Some(i * 10),
            "new",
            "active",
        )
        .await;
    }

    let state = test_state(pool);
    let resp = call_browse(&state, "?limit=20").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 20);
    assert!(
        json["next_cursor"].is_string(),
        "must provide next_cursor when more rows exist"
    );
}

// ===========================================================================
// Second page excludes first-page rows
// ===========================================================================

#[sqlx::test]
async fn pagination_second_page_excludes_first_page_rows(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    let mut first_page_ids = Vec::new();
    for i in 0..25 {
        let id = seed_listing(
            &pool,
            seller,
            cat,
            &format!("Item {i}"),
            Some(i * 10),
            "new",
            "active",
        )
        .await;
        first_page_ids.push(id);
    }

    let state = test_state(pool);

    // Page 1
    let resp1 = call_browse(&state, "?limit=20").await;
    let json1: serde_json::Value = test::read_body_json(resp1).await;
    let cursor = json1["next_cursor"].as_str().unwrap();
    let page1_ids: Vec<serde_json::Value> = json1["listings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].clone())
        .collect();

    // Page 2
    let resp2 = call_browse(&state, &format!("?limit=20&cursor={cursor}")).await;
    let json2: serde_json::Value = test::read_body_json(resp2).await;
    let page2_ids: Vec<serde_json::Value> = json2["listings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].clone())
        .collect();

    // No overlap between pages
    for id in &page2_ids {
        assert!(
            !page1_ids.contains(id),
            "page 2 must not contain page 1 id: {id}"
        );
    }
    assert_eq!(
        page2_ids.len(),
        5,
        "page 2 should have the remaining 5 items"
    );
}

// ===========================================================================
// Limit is clamped to max 50
// ===========================================================================

#[sqlx::test]
async fn limit_is_clamped_to_max_50(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    for i in 0..60 {
        seed_listing(
            &pool,
            seller,
            cat,
            &format!("Item {i}"),
            None,
            "new",
            "active",
        )
        .await;
    }

    let state = test_state(pool);
    let resp = call_browse(&state, "?limit=1000").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert!(
        listings.len() <= 50,
        "must never return more than 50 items, got {}",
        listings.len()
    );
}

// ===========================================================================
// Empty result set returns empty array and null cursor
// ===========================================================================

#[sqlx::test]
async fn empty_result_set_returns_empty_array_and_null_cursor(pool: PgPool) {
    let state = test_state(pool);
    let resp = call_browse(&state, "").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["listings"].as_array().unwrap().len(), 0);
    assert!(json["next_cursor"].is_null());
}

// ===========================================================================
// Stable ordering: identical created_at uses id tiebreak
// ===========================================================================

#[sqlx::test]
async fn stable_ordering_under_identical_created_at(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "items").await;

    // Insert two listings with manually-forced identical created_at via direct SQL
    let (_id_a, _id_b): (uuid::Uuid, uuid::Uuid) = sqlx::query_as(
        "WITH a AS (
            INSERT INTO listings (seller_id, category_id, title, description, price, condition, status, created_at)
            VALUES ($1, $2, 'Item A', '', 10, 'new', 'active', '2025-01-01 00:00:00+00')
            RETURNING id
        ), b AS (
            INSERT INTO listings (seller_id, category_id, title, description, price, condition, status, created_at)
            VALUES ($1, $2, 'Item B', '', 20, 'new', 'active', '2025-01-01 00:00:00+00')
            RETURNING id
        )
        SELECT a.id, b.id FROM a, b",
    )
    .bind(seller)
    .bind(cat)
    .fetch_one(&pool)
    .await
    .expect("seed two listings with identical created_at");

    let state = test_state(pool);

    // Run browse twice — ordering must be deterministic
    let resp1 = call_browse(&state, "").await;
    let json1: serde_json::Value = test::read_body_json(resp1).await;
    let ids1: Vec<String> = json1["listings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap().to_string())
        .collect();

    let resp2 = call_browse(&state, "").await;
    let json2: serde_json::Value = test::read_body_json(resp2).await;
    let ids2: Vec<String> = json2["listings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap().to_string())
        .collect();

    assert_eq!(ids1, ids2, "ordering must be deterministic across calls");
}
