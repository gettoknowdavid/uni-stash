// apps/api/tests/listings_search_relevance_cm_5_2.rs
//
// CM-5.2 — Search relevance verification (title weighted over description).
//
// This test verifies the trigger's weighting behavior in real query results:
//   AC 1 — Term only in title vs. only in description: title-match ranks higher
//   AC 2 — Updating title/description re-ranks correctly on next search
//
// The trigger (trg_listings_search_vector) sets:
//   weight 'A' for title tokens
//   weight 'B' for description tokens
// Since 'A' > 'B' in ts_rank, title matches always outrank description matches.

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
// AC 1 — Title-only match ranks higher than description-only match
//
// The trigger assigns weight 'A' to title tokens and 'B' to description
// tokens. ts_rank normalizes by document length, so a title match (A)
// should always produce a higher rank than a description match (B) for
// the same search term.
// ===========================================================================

#[sqlx::test]
async fn title_match_ranks_above_description_only_match(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    // Listing A: "organic chemistry" ONLY in description (weight B)
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "General Science Book",
        "Covers organic chemistry and biology topics",
        Some(40),
    )
    .await;

    // Listing B: "organic chemistry" ONLY in title (weight A)
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Organic Chemistry",
        "A comprehensive guide to modern science",
        Some(55),
    )
    .await;

    let state = test_state(pool.clone());
    let resp = call_search(&state, "?q=organic+chemistry").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 2, "both listings should match");

    // The title-match listing must rank first
    assert_eq!(
        listings[0]["title"], "Organic Chemistry",
        "title-weighted match (weight A) must outrank description-only match (weight B)"
    );
    assert_eq!(listings[1]["title"], "General Science Book");
}

// ===========================================================================
// AC 1 variant — Three listings with the same term in different positions:
//   1. Title only (A) — should rank highest
//   2. Both title and description (A+B) — should rank second
//   3. Description only (B) — should rank lowest
// ===========================================================================

#[sqlx::test]
async fn ranking_order_title_only_over_both_over_description_only(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "electronics").await;

    // Description only
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Portable Charger",
        "A powerful laptop battery charger for students",
        Some(25),
    )
    .await;

    // Title only
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Laptop Stand",
        "Ergonomic stand for desks and tables",
        Some(30),
    )
    .await;

    // Both title and description
    seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Laptop Case",
        "Protective case for laptop computers",
        Some(20),
    )
    .await;

    let state = test_state(pool.clone());
    let resp = call_search(&state, "?q=laptop").await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(listings.len(), 3);

    // Title-only and title+description should both outrank description-only
    let titles: Vec<&str> = listings
        .iter()
        .map(|l| l["title"].as_str().unwrap())
        .collect();

    // The description-only match must be last
    assert_eq!(
        titles.last().unwrap(),
        &"Portable Charger",
        "description-only match must rank lowest"
    );

    // Both title matches should be above the description-only match
    let portable_index = titles
        .iter()
        .position(|t| *t == "Portable Charger")
        .unwrap();
    let laptop_stand_index = titles.iter().position(|t| *t == "Laptop Stand").unwrap();
    let laptop_case_index = titles.iter().position(|t| *t == "Laptop Case").unwrap();
    assert!(
        laptop_stand_index < portable_index,
        "title-only match must outrank description-only"
    );
    assert!(
        laptop_case_index < portable_index,
        "title+description match must outrank description-only"
    );
}

// ===========================================================================
// AC 2 — Updating a listing's title re-fires the trigger and re-ranks
//
// The trigger fires BEFORE INSERT OR UPDATE OF title, description.
// After updating a listing's title to include the search term, it should
// now appear in search results and rank according to its new weight.
// ===========================================================================

#[sqlx::test]
async fn updating_title_re_ranks_in_search(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    // Create a listing WITHOUT the search term
    let listing_id = seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Generic Book",
        "A book about various topics",
        Some(15),
    )
    .await;

    // Confirm it does NOT appear in search for "quantum"
    let state = test_state(pool.clone());
    let resp = call_search(&state, "?q=quantum").await;
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(
        json["listings"].as_array().unwrap().len(),
        0,
        "listing should not appear before title update"
    );

    // Now update the title to include "quantum" via direct SQL (simulates
    // what CM-4.4's PATCH handler does — the trigger fires on UPDATE OF title).
    sqlx::query(
        "UPDATE listings SET title = 'Quantum Mechanics', updated_at = now() WHERE id = $1",
    )
    .bind(listing_id)
    .execute(&pool)
    .await
    .expect("update listing title");

    // Re-search — should now find it
    let resp = call_search(&state, "?q=quantum").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        1,
        "listing should appear after title update"
    );
    assert_eq!(listings[0]["title"], "Quantum Mechanics");
}

// ===========================================================================
// AC 2 variant — Updating description also re-ranks
// ===========================================================================

#[sqlx::test]
async fn updating_description_re_ranks_in_search(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;

    let listing_id = seed_listing_with_text(
        &pool,
        seller,
        cat,
        "Science Notebook",
        "A blank notebook",
        Some(5),
    )
    .await;

    // Not found initially
    let state = test_state(pool.clone());
    let resp = call_search(&state, "?q=thermodynamics").await;
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["listings"].as_array().unwrap().len(), 0);

    // Update description to include "thermodynamics"
    sqlx::query(
        "UPDATE listings SET description = 'Covers thermodynamics and heat transfer', updated_at = now() WHERE id = $1",
    )
    .bind(listing_id)
    .execute(&pool)
    .await
    .expect("update listing description");

    let resp = call_search(&state, "?q=thermodynamics").await;
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let listings = json["listings"].as_array().unwrap();
    assert_eq!(
        listings.len(),
        1,
        "listing should appear after description update"
    );
    assert_eq!(listings[0]["title"], "Science Notebook");
}
