use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::{auth::jwt, config::Config, db::Db, state::AppState};
use uni_stash_be::features::listings::{handlers::update_listing, state_machine};

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
    ).bind(school_id).bind(email).fetch_one(pool).await.unwrap()
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

async fn seed_listing(pool: &PgPool, seller: uuid::Uuid, cat: i16) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, price, condition, status)
         VALUES ($1, $2, 'Original', 'Old desc', 50, 'used', 'active') RETURNING id",
    ).bind(seller).bind(cat).fetch_one(pool).await.unwrap()
}

fn sign_token(
    keys: &uni_stash_be::core::clients::JwtKeys,
    user_id: uuid::Uuid,
    email: &str,
) -> String {
    let user = uni_stash_be::features::auth::models::User {
        id: user_id,
        school_id: 1,
        email: email.into(),
        display_name: "U".into(),
        email_verified: true,
        role: "student".into(),
        created_at: time::OffsetDateTime::now_utc(),
        updated_at: time::OffsetDateTime::now_utc(),
        password_hash: String::new(),
    };
    jwt::sign_access_token(keys, &user).unwrap()
}

async fn call_update(
    state: &web::Data<AppState>,
    listing_id: uuid::Uuid,
    body: &serde_json::Value,
    token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/listings/{id}", web::patch().to(update_listing)),
    )
    .await;
    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/listings/{listing_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(body)
        .to_request();
    test::call_service(&app, req).await
}

// ===========================================================================

#[sqlx::test]
async fn owner_can_update_active_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"title": "Updated"});
    let resp = call_update(&state, id, &body, &token).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["title"], "Updated");
    assert_eq!(json["description"], "Old desc");
}

#[sqlx::test]
async fn non_owner_gets_403(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let other = seed_user(&pool, school, "o@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, other, "o@test.edu");
    let body = serde_json::json!({"title": "Hack"});
    let resp = call_update(&state, id, &body, &token).await;
    assert_eq!(resp.status(), 403);
}

#[sqlx::test]
async fn editing_reserved_listing_returns_409(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;
    state_machine::reserve_listing(&pool, id, buyer)
        .await
        .unwrap();

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"title": "Nope"});
    let resp = call_update(&state, id, &body, &token).await;
    assert_eq!(resp.status(), 409);
}

#[sqlx::test]
async fn setting_price_to_null_makes_barter_only(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"price": null});
    let resp = call_update(&state, id, &body, &token).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert!(json["price"].is_null());
}

#[sqlx::test]
async fn partial_update_only_changes_provided_fields(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"title": "New Title"});
    let resp = call_update(&state, id, &body, &token).await;

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["title"], "New Title");
    assert_eq!(json["description"], "Old desc");
    assert_eq!(json["price"], 50);
}

#[sqlx::test]
async fn updating_title_refires_search_vector_trigger(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    // Read initial search_vector
    let sv_before: String =
        sqlx::query_scalar("SELECT search_vector::text FROM listings WHERE id = $1")
            .bind(id)
            .fetch_one(&pool)
            .await
            .unwrap();

    let state = test_state(pool.clone());
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"title": "Completely Different Title"});
    let resp = call_update(&state, id, &body, &token).await;
    assert_eq!(resp.status(), 200);

    let sv_after: String =
        sqlx::query_scalar("SELECT search_vector::text FROM listings WHERE id = $1")
            .bind(id)
            .fetch_one(&pool)
            .await
            .unwrap();

    assert_ne!(
        sv_before, sv_after,
        "search_vector must change when title is updated"
    );
}

#[sqlx::test]
async fn invalid_category_id_returns_clean_error(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let body = serde_json::json!({"category_id": 9999});
    let resp = call_update(&state, id, &body, &token).await;
    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "bad_request");
}
