use actix_web::{App, test, web};
use sqlx::{PgPool, Row};
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::auth::handlers::{delete_account, login};

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
        r2_public_url_base: "".into(),
        frontend_base_url: "https://uni-stash.com".into(),
        realtime_provider: "none".into(),
        pusher_app_id: "".into(),
        pusher_key: "".into(),
        pusher_secret: "".into(),
        pusher_cluster: "".into(),
    }
}

fn test_state(pool: PgPool) -> web::Data<AppState> {
    let db = Db { pool };
    web::Data::new(AppState::new(&test_config(), db).expect("AppState"))
}

/// Seed a school and return its ID.
async fn seed_school(pool: &PgPool, domain: &str) -> i16 {
    let result =
        sqlx::query("INSERT INTO schools (name, domain) VALUES ('Test School', $1) RETURNING id")
            .bind(domain)
            .fetch_one(pool)
            .await
            .expect("seed school");
    result.get("id")
}

#[sqlx::test]
async fn user_can_soft_delete_account(pool: PgPool) {
    let school_id = seed_school(&pool, "delete.edu").await;

    // Manually insert a verified user (signup sends OTP, so we seed directly)
    let password_hash =
        uni_stash_be::core::auth::password::hash_password("testpassword123").unwrap();
    let result = sqlx::query(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, 'delete@test.edu', $2, 'Delete Me', true)
         RETURNING id",
    )
    .bind(school_id)
    .bind(&password_hash)
    .fetch_one(&pool)
    .await
    .expect("seed user");
    let user_id: uuid::Uuid = result.get("id");

    let state = test_state(pool.clone());
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/delete-account",
        web::post().to(delete_account),
    ))
    .await;

    // Issue a JWT for the user
    let keys =
        uni_stash_be::core::clients::JwtKeys::from_pem(TEST_PRIVATE_PEM, TEST_PUBLIC_PEM).unwrap();
    let user = state
        .auth_repo
        .find_user_by_id(&user_id)
        .await
        .unwrap()
        .unwrap();
    let access_token = uni_stash_be::core::auth::jwt::sign_access_token(&keys, &user).unwrap();

    let body = serde_json::json!({
        "password": "testpassword123",
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/delete-account")
        .insert_header(("Authorization", format!("Bearer {access_token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200, "soft delete should return 200");

    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["status"], true);
    assert!(json["data"]["deletion_scheduled_at"].is_string());
    let msg = json["data"]["message"].as_str().unwrap();
    assert!(
        msg.contains("30 days"),
        "message should mention 30 days: {msg}"
    );

    // Verify the user is soft-deleted in the DB
    let row = sqlx::query("SELECT deleted_at, deletion_scheduled_at FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(row.is_some(), "user row should still exist");
    let row = row.unwrap();
    let deleted_at: Option<time::OffsetDateTime> = row.get("deleted_at");
    assert!(deleted_at.is_some(), "deleted_at should be set");
    let scheduled_at: Option<time::OffsetDateTime> = row.get("deletion_scheduled_at");
    assert!(
        scheduled_at.is_some(),
        "deletion_scheduled_at should be set"
    );
}

#[sqlx::test]
async fn delete_account_wrong_password_returns_401(pool: PgPool) {
    let school_id = seed_school(&pool, "wrongpw.edu").await;

    let password_hash =
        uni_stash_be::core::auth::password::hash_password("correctpassword").unwrap();
    let result = sqlx::query(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, 'wrongpw@test.edu', $2, 'User', true)
         RETURNING id",
    )
    .bind(school_id)
    .bind(&password_hash)
    .fetch_one(&pool)
    .await
    .expect("seed user");
    let user_id: uuid::Uuid = result.get("id");

    let state = test_state(pool);
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/delete-account",
        web::post().to(delete_account),
    ))
    .await;

    let keys =
        uni_stash_be::core::clients::JwtKeys::from_pem(TEST_PRIVATE_PEM, TEST_PUBLIC_PEM).unwrap();
    let user = state
        .auth_repo
        .find_user_by_id(&user_id)
        .await
        .unwrap()
        .unwrap();
    let access_token = uni_stash_be::core::auth::jwt::sign_access_token(&keys, &user).unwrap();

    let body = serde_json::json!({
        "password": "wrongpassword",
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/delete-account")
        .insert_header(("Authorization", format!("Bearer {access_token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401, "wrong password should return 401");
}

#[sqlx::test]
async fn delete_account_unauthenticated_returns_401(pool: PgPool) {
    let state = test_state(pool);
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/delete-account",
        web::post().to(delete_account),
    ))
    .await;

    let body = serde_json::json!({
        "password": "anypassword",
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/delete-account")
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401, "unauthenticated should return 401");
}

#[sqlx::test]
async fn soft_deleted_user_cannot_login(pool: PgPool) {
    let school_id = seed_school(&pool, "softdel.edu").await;

    let password_hash = uni_stash_be::core::auth::password::hash_password("mypassword123").unwrap();
    sqlx::query(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified, deleted_at, deletion_scheduled_at)
         VALUES ($1, 'softdel@test.edu', $2, 'Soft Deleted', true, now(), now() + interval '30 days')",
    )
    .bind(school_id)
    .bind(&password_hash)
    .execute(&pool)
    .await
    .expect("seed soft-deleted user");

    let state = test_state(pool);
    let app = test::init_service(
        App::new()
            .app_data(state.clone())
            .route("/api/v1/auth/login", web::post().to(login)),
    )
    .await;

    let body = serde_json::json!({
        "email": "softdel@test.edu",
        "password": "mypassword123",
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/login")
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.status(),
        401,
        "soft-deleted user should not be able to login"
    );
}

#[sqlx::test]
async fn delete_account_already_soft_deleted_returns_400(pool: PgPool) {
    let school_id = seed_school(&pool, "alreadysdel.edu").await;

    let password_hash = uni_stash_be::core::auth::password::hash_password("mypassword123").unwrap();
    let result = sqlx::query(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified, deleted_at, deletion_scheduled_at)
         VALUES ($1, 'alreadysdel@test.edu', $2, 'Already Deleted', true, now(), now() + interval '30 days')
         RETURNING id",
    )
    .bind(school_id)
    .bind(&password_hash)
    .fetch_one(&pool)
    .await
    .expect("seed soft-deleted user");
    let user_id: uuid::Uuid = result.get("id");

    let state = test_state(pool);
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/delete-account",
        web::post().to(delete_account),
    ))
    .await;

    // Issue JWT for the already-soft-deleted user using the private helper.
    // We fetch the user with deleted_at included, then sign with the standard
    // function — the JWT itself is valid; the handler should detect the
    // soft-delete state via find_user_by_id_including_deleted.
    let keys =
        uni_stash_be::core::clients::JwtKeys::from_pem(TEST_PRIVATE_PEM, TEST_PUBLIC_PEM).unwrap();
    let user = state
        .auth_repo
        .find_user_by_id_including_deleted(&user_id)
        .await
        .unwrap()
        .expect("user should exist including deleted");
    let access_token = uni_stash_be::core::auth::jwt::sign_access_token(&keys, &user).unwrap();

    let body = serde_json::json!({
        "password": "mypassword123",
    });

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/delete-account")
        .insert_header(("Authorization", format!("Bearer {access_token}")))
        .set_json(&body)
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.status(),
        400,
        "already soft-deleted account should return 400"
    );
}
