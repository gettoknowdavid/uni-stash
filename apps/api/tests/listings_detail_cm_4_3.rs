use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::{config::Config, db::Db, state::AppState};
use uni_stash_be::features::listings::handlers::get_listing_detail;

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
    sqlx::query_scalar("INSERT INTO schools (name, domain) VALUES ('T', 't.edu') RETURNING id")
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn seed_user(pool: &PgPool, school_id: i16, email: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name) VALUES ($1, $2, 'h', 'U') RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn seed_category(pool: &PgPool, slug: &str) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ($1, $1) RETURNING id",
    )
    .bind(slug)
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn seed_listing(
    pool: &PgPool,
    seller_id: uuid::Uuid,
    category_id: i16,
    status: &str,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Item', 'Desc', 'new', $3) RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .bind(status)
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn seed_image(pool: &PgPool, listing_id: uuid::Uuid, key: &str, pos: i16) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO images (listing_id, object_key, position) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(listing_id)
    .bind(key)
    .bind(pos)
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn call_detail(
    state: &web::Data<AppState>,
    listing_id: uuid::Uuid,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/listings/{id}", web::get().to(get_listing_detail)),
    )
    .await;
    let req = test::TestRequest::get()
        .uri(&format!("/api/v1/listings/{listing_id}"))
        .to_request();
    test::call_service(&app, req).await
}

// ===========================================================================

#[sqlx::test]
async fn active_listing_returns_full_detail(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "books").await;
    let listing_id = seed_listing(&pool, seller, cat, "active").await;
    seed_image(&pool, listing_id, "key1.jpg", 0).await;
    seed_image(&pool, listing_id, "key2.jpg", 1).await;

    let state = test_state(pool);
    let resp = call_detail(&state, listing_id).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], "success");
    let data = json["data"].as_object().expect("data");
    assert_eq!(data["id"], listing_id.to_string());
    assert_eq!(data["title"], "Item");
    assert_eq!(data["seller"]["id"], seller.to_string());
    assert_eq!(data["seller"]["display_name"], "U");
    assert_eq!(data["category"]["slug"], "books");
    assert_eq!(data["images"].as_array().unwrap().len(), 2);
}

#[sqlx::test]
async fn nonexistent_id_returns_404(pool: PgPool) {
    let state = test_state(pool);
    let fake_id = uuid::Uuid::new_v4();
    let resp = call_detail(&state, fake_id).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn deleted_listing_returns_404_to_anonymous(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "deleted").await;

    let state = test_state(pool);
    let resp = call_detail(&state, id).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn images_returned_in_position_order(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "active").await;
    seed_image(&pool, id, "c.jpg", 2).await;
    seed_image(&pool, id, "a.jpg", 0).await;
    seed_image(&pool, id, "b.jpg", 1).await;

    let state = test_state(pool);
    let resp = call_detail(&state, id).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let images = json["data"]["images"].as_array().unwrap();
    assert_eq!(images.len(), 3);
    assert_eq!(images[0]["position"], 0);
    assert_eq!(images[1]["position"], 1);
    assert_eq!(images[2]["position"], 2);
}
