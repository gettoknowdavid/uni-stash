use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::{auth::jwt, config::Config, db::Db, state::AppState};
use uni_stash_be::features::listings::{
    handlers::{delete_listing, list_listings},
    state_machine,
};

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

async fn seed_school(p: &PgPool) -> i16 {
    sqlx::query_scalar("INSERT INTO schools (name, domain) VALUES ('T', 't.edu') RETURNING id")
        .fetch_one(p)
        .await
        .unwrap()
}
async fn seed_user(p: &PgPool, s: i16, e: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name) VALUES ($1, $2, 'h', 'U') RETURNING id",
    ).bind(s).bind(e).fetch_one(p).await.unwrap()
}
async fn seed_category(p: &PgPool, slug: &str) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ($1, $1) RETURNING id",
    )
    .bind(slug)
    .fetch_one(p)
    .await
    .unwrap()
}
async fn seed_listing(p: &PgPool, seller: uuid::Uuid, cat: i16) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Item', '', 'new', 'active') RETURNING id",
    )
    .bind(seller)
    .bind(cat)
    .fetch_one(p)
    .await
    .unwrap()
}

fn sign_token(keys: &uni_stash_be::core::clients::JwtKeys, uid: uuid::Uuid, email: &str) -> String {
    let user = uni_stash_be::features::auth::models::User {
        id: uid,
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

async fn call_delete(
    state: &web::Data<AppState>,
    id: uuid::Uuid,
    token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/listings/{id}", web::delete().to(delete_listing)),
    )
    .await;
    let req = test::TestRequest::delete()
        .uri(&format!("/api/v1/listings/{id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .to_request();
    test::call_service(&app, req).await
}

async fn call_browse(state: &web::Data<AppState>) -> serde_json::Value {
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/listings", web::get().to(list_listings)),
    )
    .await;
    let req = test::TestRequest::get()
        .uri("/api/v1/listings")
        .to_request();
    let resp = test::call_service(&app, req).await;
    test::read_body_json(resp).await
}

async fn listing_status(pool: &PgPool, id: uuid::Uuid) -> String {
    sqlx::query_scalar::<_, String>("SELECT status FROM listings WHERE id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn listing_exists(pool: &PgPool, id: uuid::Uuid) -> bool {
    sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM listings WHERE id = $1)")
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap()
}

// ===========================================================================

#[sqlx::test]
async fn owner_can_soft_delete_active_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool.clone());
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let resp = call_delete(&state, id, &token).await;
    assert_eq!(resp.status(), 204);
    assert_eq!(listing_status(&pool, id).await, "deleted");
}

#[sqlx::test]
async fn owner_can_soft_delete_reserved_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;
    state_machine::reserve_listing(&pool, id, buyer)
        .await
        .unwrap();

    let state = test_state(pool.clone());
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let resp = call_delete(&state, id, &token).await;
    assert_eq!(resp.status(), 204);
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
    let resp = call_delete(&state, id, &token).await;
    assert_eq!(resp.status(), 403);
}

#[sqlx::test]
async fn nonexistent_listing_gets_404(pool: PgPool) {
    let school = seed_school(&pool).await;
    let user = seed_user(&pool, school, "u@test.edu").await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, user, "u@test.edu");
    let resp = call_delete(&state, uuid::Uuid::new_v4(), &token).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn deleted_listing_excluded_from_default_browse(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool.clone());
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");

    // Confirm it shows up before delete
    let json = call_browse(&state).await;
    assert!(
        json["listings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|l| l["id"] == id.to_string())
    );

    // Delete
    let resp = call_delete(&state, id, &token).await;
    assert_eq!(resp.status(), 204);

    // Confirm it's gone from browse
    let json = call_browse(&state).await;
    assert!(
        !json["listings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|l| l["id"] == id.to_string())
    );
}

#[sqlx::test]
async fn deleted_listing_row_still_exists_in_db(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat).await;

    let state = test_state(pool.clone());
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    call_delete(&state, id, &token).await;

    // Row still exists — it's a soft delete
    assert!(
        listing_exists(&pool, id).await,
        "soft delete must not hard-delete the row"
    );
}
