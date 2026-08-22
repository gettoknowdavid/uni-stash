use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::{auth::jwt, config::Config, db::Db, state::AppState};
use uni_stash_be::features::listings::{handlers::reserve_listing, state_machine};

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
async fn seed_listing(p: &PgPool, seller: uuid::Uuid, cat: i16, status: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Item', '', 'new', $3) RETURNING id",
    )
    .bind(seller)
    .bind(cat)
    .bind(status)
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

async fn call_reserve(
    state: &web::Data<AppState>,
    id: uuid::Uuid,
    token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/listings/{id}/reserve",
        web::post().to(reserve_listing),
    ))
    .await;
    let req = test::TestRequest::post()
        .uri(&format!("/api/v1/listings/{id}/reserve"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .to_request();
    test::call_service(&app, req).await
}

#[derive(sqlx::FromRow)]
struct ListingState {
    status: String,
    reserved_by: Option<uuid::Uuid>,
}

async fn get_listing_state(pool: &PgPool, id: uuid::Uuid) -> ListingState {
    sqlx::query_as::<_, ListingState>("SELECT status, reserved_by FROM listings WHERE id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap()
}

// ===========================================================================

#[sqlx::test]
async fn buyer_can_reserve_active_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, buyer, "b@test.edu");
    let resp = call_reserve(&state, id, &token).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], "reserved");
    assert_eq!(json["reserved_by"], buyer.to_string());
}

#[sqlx::test]
async fn reserving_already_reserved_returns_409(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let b1 = seed_user(&pool, school, "b1@test.edu").await;
    let b2 = seed_user(&pool, school, "b2@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    // First reserve succeeds
    state_machine::reserve_listing(&pool, id, b1).await.unwrap();

    // Second reserve fails
    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, b2, "b2@test.edu");
    let resp = call_reserve(&state, id, &token).await;
    assert_eq!(resp.status(), 409);
}

#[sqlx::test]
async fn reserving_own_listing_returns_400(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, seller, "s@test.edu");
    let resp = call_reserve(&state, id, &token).await;
    assert_eq!(resp.status(), 400);
}

#[sqlx::test]
async fn reserving_nonexistent_returns_404(pool: PgPool) {
    let school = seed_school(&pool).await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;

    let state = test_state(pool);
    let token = sign_token(&state.jwt_keys, buyer, "b@test.edu");
    let resp = call_reserve(&state, uuid::Uuid::new_v4(), &token).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn concurrent_reserve_attempts_exactly_one_succeeds(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let b1 = seed_user(&pool, school, "b1@test.edu").await;
    let b2 = seed_user(&pool, school, "b2@test.edu").await;
    let cat = seed_category(&pool, "x").await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    let (r1, r2) = tokio::join!(
        state_machine::reserve_listing(&pool, id, b1),
        state_machine::reserve_listing(&pool, id, b2),
    );

    let successes = [r1.is_ok(), r2.is_ok()].iter().filter(|&&x| x).count();
    assert_eq!(successes, 1, "exactly one reserve must succeed");

    let state = get_listing_state(&pool, id).await;
    assert_eq!(state.status, "reserved");
    assert!(state.reserved_by.is_some());
}
