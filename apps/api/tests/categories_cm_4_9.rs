use actix_web::{App, test, web};
use sqlx::PgPool;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::categories::handlers::list_categories;

// ---------------------------------------------------------------------------
// Test harness (same shape as schools_cm.rs)
// ---------------------------------------------------------------------------

fn test_config() -> Config {
    Config {
        database_url: "postgres://localhost:5432/uni_stash".into(),
        jwt_private_key: include_str!("fixtures/test_rsa_private.pem").into(),
        jwt_public_key: include_str!("fixtures/test_rsa_public.pem").into(),
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

/// Helper: build an Actix test app with the categories route wired.
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
}

// ===========================================================================
// GET /api/v1/categories — list all categories (public)
// ===========================================================================

#[sqlx::test]
async fn list_categories_returns_all_categories(pool: PgPool) {
    sqlx::query(
        "INSERT INTO categories (slug, label, sort_order)
         VALUES ('electronics', 'Electronics', 1), ('textbooks', 'Textbooks', 0)",
    )
    .execute(&pool)
    .await
    .expect("seed categories");

    let state = test_state(pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::get()
        .uri("/api/v1/categories")
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], true);
    let categories = json["data"]["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 2);

    // Ordered by sort_order ASC: textbooks (0) before electronics (1).
    assert_eq!(categories[0]["slug"], "textbooks");
    assert_eq!(categories[0]["label"], "Textbooks");
    assert_eq!(categories[1]["slug"], "electronics");
    assert_eq!(categories[1]["label"], "Electronics");

    // Wire format per CM-4.9: numeric id, slug, label.
    assert_eq!(categories[0]["id"], 1);
}

#[sqlx::test]
async fn list_categories_orders_ties_by_label(pool: PgPool) {
    // Same sort_order → tiebreak on label ASC.
    sqlx::query(
        "INSERT INTO categories (slug, label, sort_order)
         VALUES ('zeta', 'Zeta', 5), ('alpha', 'Alpha', 5), ('mu', 'Mu', 5)",
    )
    .execute(&pool)
    .await
    .expect("seed categories");

    let state = test_state(pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::get()
        .uri("/api/v1/categories")
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    let slugs: Vec<&str> = json["data"]["categories"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["slug"].as_str().unwrap())
        .collect();
    assert_eq!(slugs, vec!["alpha", "mu", "zeta"]);
}

#[sqlx::test]
async fn list_categories_empty_returns_empty_array(pool: PgPool) {
    let state = test_state(pool);
    let app = test::init_service(categories_app(state)).await;

    let req = test::TestRequest::get()
        .uri("/api/v1/categories")
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], true);
    assert_eq!(json["data"]["categories"].as_array().unwrap().len(), 0);
}
