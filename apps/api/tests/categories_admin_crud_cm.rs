use actix_web::{App, test, web};
use sqlx::{PgPool, Row};
use uni_stash_be::core::auth::admin_jwt;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::categories::handlers::{
    create_category, delete_category, list_categories, update_category,
};

const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

// ---------------------------------------------------------------------------
// Helpers (same shape as schools_cm.rs)
// ---------------------------------------------------------------------------

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
        r2_public_url_base: "".into(),
        frontend_base_url: "https://uni-stash.com".into(),
        realtime_provider: "none".into(),
        pusher_app_id: "".into(),
        pusher_key: "".into(),
        pusher_secret: "".into(),
        pusher_cluster: "".into(),
        pusher_instance_id: "".into(),
        pusher_secret_key: "".into(),
        metrics_enabled: false,
        metrics_token: "".into(),
    }
}

fn test_state(pool: &PgPool) -> web::Data<AppState> {
    let db = Db { pool: pool.clone() };
    web::Data::new(AppState::new(&test_config(), db).expect("AppState"))
}

/// Seed an admin in the `admins` table and return their ID.
async fn seed_admin(pool: &PgPool, email: &str, level: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        r#"INSERT INTO admins (email, password_hash, display_name, level)
           VALUES ($1, 'hash', 'Admin User', $2)
           ON CONFLICT (email) DO UPDATE SET level = $2
           RETURNING id"#,
    )
    .bind(email)
    .bind(level)
    .fetch_one(pool)
    .await
    .expect("seed admin")
}

// /// Seed a verified user (for creating listings to test delete guards).
// async fn seed_user(pool: &PgPool) -> uuid::Uuid {
//     sqlx::query_scalar::<_, uuid::Uuid>(
//         "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)\n           VALUES (NULL, $1, 'hash', 'Test User', true) RETURNING id",
//     )
//     .bind(format!("user-{}@test.edu", uuid::Uuid::new_v4()))
//     .fetch_one(pool)
//     .await
//     .expect("seed user")
// }

/// Sign an admin access token for the given admin ID and level.
fn sign_admin_token(admin_id: uuid::Uuid, level: &str) -> String {
    let keys = uni_stash_be::core::clients::JwtKeys::from_pem(TEST_PRIVATE_PEM, TEST_PUBLIC_PEM)
        .expect("jwt keys");
    admin_jwt::sign_admin_access_token(&keys, admin_id, level).expect("sign admin token")
}

/// Helper: build an Actix test app with all category routes wired.
fn categories_app(
    state: web::Data<AppState>,
) -> actix_web::App<
    impl actix_web::dev::ServiceFactory<
        actix_web::dev::ServiceRequest,
        Response = actix_web::dev::ServiceResponse<actix_web::body::BoxBody>,
        Config = (),
        InitError = (),
        Error = actix_web::Error,
    >,
> {
    App::new()
        .app_data(state.clone())
        .route("/api/v1/categories", web::get().to(list_categories))
        .route("/api/v1/categories", web::post().to(create_category))
        .route("/api/v1/categories/{id}", web::patch().to(update_category))
        .route("/api/v1/categories/{id}", web::delete().to(delete_category))
}

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

// async fn seed_listing(pool: &PgPool, seller_id: uuid::Uuid, category_id: i16) -> uuid::Uuid {
//     sqlx::query_scalar::<_, uuid::Uuid>(
//         r#"INSERT INTO listings (seller_id, category_id, title, description, condition, status)
//            VALUES ($1, $2, 'Test Listing', 'desc', 'used', 'active')
//            RETURNING id"#,
//     )
//     .bind(seller_id)
//     .bind(category_id)
//     .fetch_one(pool)
//     .await
//     .expect("seed listing")
// }

// ===========================================================================
// GET /api/v1/categories — public read (unchanged behaviour)
// ===========================================================================

#[sqlx::test]
async fn list_categories_requires_no_auth(pool: PgPool) {
    seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::get()
        .uri("/api/v1/categories")
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], true);
    let categories = json["data"]["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0]["slug"], "textbooks");
}

// ===========================================================================
// POST /api/v1/categories — admin-only create
// ===========================================================================

#[sqlx::test]
async fn super_admin_can_create_category(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({
        "slug": "sports-equipment",
        "label": "Sports Equipment",
        "sort_order": 10,
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 201);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], true);
    let data = json["data"].as_object().expect("data");
    assert_eq!(data["slug"], "sports-equipment");
    assert_eq!(data["label"], "Sports Equipment");
    assert_eq!(data["message"], "category created successfully");
    assert!(data["id"].is_number());

    // Persisted and ordered by the new sort_order.
    let row = sqlx::query("SELECT sort_order FROM categories WHERE slug = 'sports-equipment'")
        .fetch_one(&pool)
        .await
        .expect("fetch category");
    assert_eq!(row.get::<i16, _>("sort_order"), 10);
}

#[sqlx::test]
async fn create_category_defaults_sort_order_to_zero(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "gadgets", "label": "Gadgets" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 201);

    let row = sqlx::query("SELECT sort_order FROM categories WHERE slug = 'gadgets'")
        .fetch_one(&pool)
        .await
        .expect("fetch category");
    assert_eq!(row.get::<i16, _>("sort_order"), 0);
}

#[sqlx::test]
async fn create_category_duplicate_slug_returns_409(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "textbooks", "label": "Books Again" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 409, "duplicate slug should return 409");
}

#[sqlx::test]
async fn create_category_invalid_slug_returns_422(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    // Uppercase and spaces are rejected by the slug regex.
    let body = serde_json::json!({ "slug": "Invalid Slug!", "label": "Bad" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 422);
}

#[sqlx::test]
async fn unauthenticated_cannot_create_category_returns_401(pool: PgPool) {
    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "sneaky", "label": "Sneaky" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}

#[sqlx::test]
async fn invalid_token_cannot_create_category_returns_401(pool: PgPool) {
    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "sneaky", "label": "Sneaky" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", "Bearer invalid.token.here"))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}

#[sqlx::test]
async fn standard_admin_without_permission_cannot_create_category_returns_403(pool: PgPool) {
    // Standard admin with no "categories" entry in permissions JSONB.
    let admin_id = seed_admin(&pool, "standard@test.edu", "standard").await;
    let token = sign_admin_token(admin_id, "standard");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "forbidden", "label": "Forbidden" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 403);
}

#[sqlx::test]
async fn standard_admin_with_categories_write_permission_can_create(pool: PgPool) {
    let admin_id = seed_admin(&pool, "permitted@test.edu", "standard").await;
    // Grant explicit permission.
    sqlx::query("UPDATE admins SET permissions = '{\"categories\": [\"write\"]}' WHERE id = $1")
        .bind(admin_id)
        .execute(&pool)
        .await
        .expect("grant permission");
    let token = sign_admin_token(admin_id, "standard");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "granted", "label": "Granted" });
    let req = test::TestRequest::post()
        .uri("/api/v1/categories")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 201);
}

// ===========================================================================
// PATCH /api/v1/categories/{id} — admin-only update
// ===========================================================================

#[sqlx::test]
async fn super_admin_can_update_category_label_and_sort_order(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    let category_id = seed_category(&pool, "textbooks", "Textbooks").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "label": "Course Books", "sort_order": 2 });
    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["data"]["label"], "Course Books");
    assert_eq!(json["data"]["slug"], "textbooks");

    let row = sqlx::query("SELECT sort_order FROM categories WHERE id = $1")
        .bind(category_id)
        .fetch_one(&pool)
        .await
        .expect("fetch category");
    assert_eq!(row.get::<i16, _>("sort_order"), 2);
}

#[sqlx::test]
async fn update_category_can_change_slug(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    let category_id = seed_category(&pool, "old-slug", "Old").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "new-slug" });
    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["data"]["slug"], "new-slug");
}

#[sqlx::test]
async fn update_category_to_duplicate_slug_returns_409(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    seed_category(&pool, "taken", "Taken").await;
    let category_id = seed_category(&pool, "other", "Other").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "slug": "taken" });
    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 409);
}

#[sqlx::test]
async fn update_missing_category_returns_404(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let body = serde_json::json!({ "label": "Ghost" });
    let req = test::TestRequest::patch()
        .uri("/api/v1/categories/9999")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn update_category_with_empty_body_returns_400(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    let category_id = seed_category(&pool, "stable", "Stable").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .set_json(serde_json::json!({}))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 400);
}

#[sqlx::test]
async fn unauthenticated_cannot_update_category_returns_401(pool: PgPool) {
    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let category_id = seed_category(&pool, "locked", "Locked").await;

    let req = test::TestRequest::patch()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .set_json(serde_json::json!({ "label": "Hacked" }))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}

// ===========================================================================
// DELETE /api/v1/categories/{id} — admin-only delete with listing guard
// ===========================================================================

#[sqlx::test]
async fn super_admin_can_delete_empty_category(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");
    let category_id = seed_category(&pool, "empty", "Empty").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::delete()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 204);

    let remaining: Option<i16> = sqlx::query_scalar("SELECT id FROM categories WHERE id = $1")
        .bind(category_id)
        .fetch_optional(&pool)
        .await
        .expect("fetch category");
    assert!(remaining.is_none(), "category must be gone");
}

// #[sqlx::test]
// async fn delete_category_with_listings_returns_409_and_preserves_data(pool: PgPool) {
//     let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
//     let token = sign_admin_token(admin_id, "super");
//     let category_id = seed_category(&pool, "in-use", "In Use").await;
//     let user_id = seed_user(&pool).await;
//     let listing_id = seed_listing(&pool, user_id, category_id).await;

//     let state = test_state(&pool);
//     let app = test::init_service(categories_app(state)).await;

//     let req = test::TestRequest::delete()
//         .uri(&format!("/api/v1/categories/{category_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(
//         resp.status(),
//         409,
//         "deleting an in-use category must be refused"
//     );

//     // Category and its listing must both still exist.
//     let still_there: Option<i16> = sqlx::query_scalar("SELECT id FROM categories WHERE id = $1")
//         .bind(category_id)
//         .fetch_optional(&pool)
//         .await
//         .expect("fetch category");
//     assert!(
//         still_there.is_some(),
//         "category must survive the refused delete"
//     );

//     let listing_alive: Option<uuid::Uuid> =
//         sqlx::query_scalar("SELECT id FROM listings WHERE id = $1")
//             .bind(listing_id)
//             .fetch_optional(&pool)
//             .await
//             .expect("fetch listing");
//     assert!(
//         listing_alive.is_some(),
//         "listings must survive the refused delete"
//     );
// }

#[sqlx::test]
async fn delete_missing_category_returns_404(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::delete()
        .uri("/api/v1/categories/9999")
        .insert_header(("Authorization", format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 404);
}

#[sqlx::test]
async fn unauthenticated_cannot_delete_category_returns_401(pool: PgPool) {
    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let category_id = seed_category(&pool, "protected", "Protected").await;

    let req = test::TestRequest::delete()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);

    // Category still present.
    let still_there: Option<i16> = sqlx::query_scalar("SELECT id FROM categories WHERE id = $1")
        .bind(category_id)
        .fetch_optional(&pool)
        .await
        .expect("fetch category");
    assert!(still_there.is_some());
}

#[sqlx::test]
async fn standard_admin_without_permission_cannot_delete_category(pool: PgPool) {
    let admin_id = seed_admin(&pool, "plain@test.edu", "standard").await;
    let token = sign_admin_token(admin_id, "standard");
    let category_id = seed_category(&pool, "locked-away", "Locked").await;

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::delete()
        .uri(&format!("/api/v1/categories/{category_id}"))
        .insert_header(("Authorization", format!("Bearer {token}")))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 403);
}

// ===========================================================================
// End-to-end: create → appears in public list → update → delete
// ===========================================================================

#[sqlx::test]
async fn full_lifecycle_create_list_update_delete(pool: PgPool) {
    let admin_id = seed_admin(&pool, "admin@test.edu", "super").await;
    let token = sign_admin_token(admin_id, "super");

    let state = test_state(&pool);
    let app = test::init_service(categories_app(state)).await;
    let auth = ("Authorization", format!("Bearer {token}"));

    // 1. Create
    let resp = test::call_service(
        &app,
        test::TestRequest::post()
            .uri("/api/v1/categories")
            .insert_header(auth.clone())
            .set_json(serde_json::json!({ "slug": "lifecycle", "label": "Lifecycle" }))
            .to_request(),
    )
    .await;
    assert_eq!(resp.status(), 201);
    let json: serde_json::Value = test::read_body_json(resp).await;
    let category_id = json["data"]["id"].as_i64().unwrap();

    // 2. Public list shows it
    let resp = test::call_service(
        &app,
        test::TestRequest::get()
            .uri("/api/v1/categories")
            .to_request(),
    )
    .await;
    let json: serde_json::Value = test::read_body_json(resp).await;
    let slugs: Vec<&str> = json["data"]["categories"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["slug"].as_str().unwrap())
        .collect();
    assert!(slugs.contains(&"lifecycle"));

    // 3. Update
    let resp = test::call_service(
        &app,
        test::TestRequest::patch()
            .uri(&format!("/api/v1/categories/{category_id}"))
            .insert_header(auth.clone())
            .set_json(serde_json::json!({ "label": "Lifecycle v2" }))
            .to_request(),
    )
    .await;
    assert_eq!(resp.status(), 200);

    // 4. Delete
    let resp = test::call_service(
        &app,
        test::TestRequest::delete()
            .uri(&format!("/api/v1/categories/{category_id}"))
            .insert_header(auth)
            .to_request(),
    )
    .await;
    assert_eq!(resp.status(), 204);
}
