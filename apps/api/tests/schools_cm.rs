// use actix_web::{App, test, web};
// use sqlx::{PgPool, Row};
// use uni_stash_be::core::auth::jwt;
// use uni_stash_be::core::config::Config;
// use uni_stash_be::core::db::Db;
// use uni_stash_be::core::state::AppState;
// use uni_stash_be::features::auth::models::User;
// use uni_stash_be::features::schools::handlers::{
//     create_school, delete_school, get_school, list_schools, update_school,
// };

// const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
// const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

// // ---------------------------------------------------------------------------
// // Helpers
// // ---------------------------------------------------------------------------

// fn test_config() -> Config {
//     Config {
//         database_url: "postgres://localhost:5432/uni_stash".into(),
//         jwt_private_key: TEST_PRIVATE_PEM.into(),
//         jwt_public_key: TEST_PUBLIC_PEM.into(),
//         smtp_host: "smtp.example.com".into(),
//         smtp_port: 587,
//         smtp_user: "test@example.com".into(),
//         smtp_password: "test_password".into(),
//         smtp_from: "Test <test@example.com>".into(),
//         port: 8080,
//         env: "test".into(),
//         r2_bucket: "".into(),
//         r2_access_key_id: "".into(),
//         r2_secret_access_key: "".into(),
//         r2_endpoint: "".into(),
//         frontend_base_url: "https://uni-stash.com".into(),
//     }
// }

// fn test_state(pool: PgPool) -> web::Data<AppState> {
//     let db = Db { pool };
//     web::Data::new(AppState::new(&test_config(), db).expect("AppState"))
// }

// /// Seed a user with the given role and return their ID.
// async fn seed_user_with_role(pool: &PgPool, email: &str, role: &str) -> uuid::Uuid {
//     // First ensure a school exists for the FK
//     let _ = sqlx::query!(
//         "INSERT INTO schools (name, domain) VALUES ('Test University', 'test.edu')
//          ON CONFLICT (domain) DO NOTHING"
//     )
//     .execute(pool)
//     .await
//     .expect("seed school");

//     sqlx::query_scalar::<_, uuid::Uuid>(
//         "INSERT INTO users (school_id, email, password_hash, display_name, role)
//          VALUES (1, $1, 'hash', 'Test User', $2)
//          ON CONFLICT (email) DO UPDATE SET role = $2
//          RETURNING id",
//     )
//     .bind(email)
//     .bind(role)
//     .fetch_one(pool)
//     .await
//     .expect("seed user")
// }

// fn sign_access_token_for_user(user: &User) -> String {
//     let keys = uni_stash_be::core::clients::JwtKeys::from_pem(TEST_PRIVATE_PEM, TEST_PUBLIC_PEM)
//         .expect("jwt keys");
//     jwt::sign_access_token(&keys, user).expect("sign access token")
// }

// fn make_user_model(id: uuid::Uuid, email: &str, role: &str) -> User {
//     User {
//         id,
//         school_id: 1,
//         email: email.to_string(),
//         password_hash: String::new(),
//         display_name: "Test User".to_string(),
//         email_verified: true,
//         role: role.to_string(),
//         created_at: time::OffsetDateTime::now_utc(),
//         updated_at: time::OffsetDateTime::now_utc(),
//     }
// }

// /// Helper: build an Actix test app with all school routes wired.
// fn school_app(
//     state: web::Data<AppState>,
// ) -> actix_web::App<
//     impl actix_web::dev::ServiceFactory<
//         actix_web::dev::ServiceRequest,
//         Response = actix_web::dev::ServiceResponse<actix_web::body::BoxBody>,
//         Config = (),
//         InitError = (),
//         Error = actix_web::Error,
//     >,
// > {
//     App::new()
//         .app_data(state.clone())
//         .route("/api/v1/schools", web::get().to(list_schools))
//         .route("/api/v1/schools/{id}", web::get().to(get_school))
//         .route("/api/v1/schools", web::post().to(create_school))
//         .route("/api/v1/schools/{id}", web::patch().to(update_school))
//         .route("/api/v1/schools/{id}", web::delete().to(delete_school))
// }

// // ===========================================================================
// // GET /api/v1/schools — list all schools (public)
// // ===========================================================================

// #[sqlx::test]
// async fn list_schools_returns_all_schools(pool: PgPool) {
//     // Seed some schools directly via SQL
//     sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni A', 'a.edu'), ('Uni B', 'b.edu')")
//         .execute(&pool)
//         .await
//         .expect("seed schools");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get().uri("/api/v1/schools").to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     let schools = json["data"]["schools"].as_array().unwrap();
//     assert!(schools.len() >= 2, "should return at least 2 schools");

//     // Should be ordered by name ASC
//     let names: Vec<&str> = schools
//         .iter()
//         .map(|s| s["name"].as_str().unwrap())
//         .collect();
//     let mut sorted_names = names.clone();
//     sorted_names.sort();
//     assert_eq!(names, sorted_names, "schools should be sorted by name");
// }

// #[sqlx::test]
// async fn list_schools_empty_returns_empty_array(pool: PgPool) {
//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get().uri("/api/v1/schools").to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     assert_eq!(json["data"]["schools"].as_array().unwrap().len(), 0);
// }

// // ===========================================================================
// // GET /api/v1/schools/{id} — get single school (public)
// // ===========================================================================

// #[sqlx::test]
// async fn get_school_returns_school(pool: PgPool) {
//     let result = sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Test Uni', 'test.edu') RETURNING id",
//     )
//     .fetch_one(&pool)
//     .await
//     .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     assert_eq!(json["status"], true);
//     assert_eq!(json["data"]["name"], "Test Uni");
//     assert_eq!(json["data"]["domain"], "test.edu");
// }

// #[sqlx::test]
// async fn get_school_not_found_returns_404(pool: PgPool) {
//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get()
//         .uri("/api/v1/schools/9999")
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 404);
// }

// // ===========================================================================
// // POST /api/v1/schools — create school (admin-only)
// // ===========================================================================

// #[sqlx::test]
// async fn admin_can_create_school(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "University of Lagos",
//         "domain": "unilag.edu.ng",
//     });

//     let req = test::TestRequest::post()
//         .uri("/api/v1/schools")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 201);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     assert_eq!(json["status"], true);
//     let data = json["data"].as_object().expect("data");
//     assert_eq!(data["name"], "University of Lagos");
//     assert_eq!(data["domain"], "unilag.edu.ng");
//     assert_eq!(data["message"], "school created successfully");
//     assert!(data["id"].is_number());
// }

// #[sqlx::test]
// async fn non_admin_cannot_create_school_returns_403(pool: PgPool) {
//     let student_id = seed_user_with_role(&pool, "student@test.edu", "student").await;
//     let student_user = make_user_model(student_id, "student@test.edu", "student");
//     let token = sign_access_token_for_user(&student_user);

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "Should Fail University",
//         "domain": "fail.edu",
//     });

//     let req = test::TestRequest::post()
//         .uri("/api/v1/schools")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 403);
// }

// #[sqlx::test]
// async fn unauthenticated_cannot_create_school_returns_401(pool: PgPool) {
//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "No Auth University",
//         "domain": "noauth.edu",
//     });

//     let req = test::TestRequest::post()
//         .uri("/api/v1/schools")
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 401);
// }

// #[sqlx::test]
// async fn create_school_duplicate_domain_returns_409(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     // Seed an existing school with the same domain
//     sqlx::query("INSERT INTO schools (name, domain) VALUES ('Existing', 'dup.edu')")
//         .execute(&pool)
//         .await
//         .expect("seed existing school");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "Duplicate Domain University",
//         "domain": "dup.edu",
//     });

//     let req = test::TestRequest::post()
//         .uri("/api/v1/schools")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(
//         resp.status(),
//         409,
//         "duplicate domain should return 409 Conflict"
//     );
// }

// #[sqlx::test]
// async fn create_school_validation_error_returns_422(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     // Name too short (min 2 chars)
//     let body = serde_json::json!({
//         "name": "X",
//         "domain": "valid.edu",
//     });

//     let req = test::TestRequest::post()
//         .uri("/api/v1/schools")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 422, "short name should return 422");
// }

// // ===========================================================================
// // PATCH /api/v1/schools/{id} — update school (admin-only)
// // ===========================================================================

// #[sqlx::test]
// async fn admin_can_update_school_name(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let result = sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Old Name', 'old.edu') RETURNING id",
//     )
//     .fetch_one(&pool)
//     .await
//     .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "New Name",
//     });

//     let req = test::TestRequest::patch()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     assert_eq!(json["data"]["school"]["name"], "New Name");
//     assert_eq!(
//         json["data"]["school"]["domain"], "old.edu",
//         "domain should be unchanged"
//     );
// }

// #[sqlx::test]
// async fn admin_can_update_school_domain(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let result =
//         sqlx::query("INSERT INTO schools (name, domain) VALUES ('My Uni', 'old.edu') RETURNING id")
//             .fetch_one(&pool)
//             .await
//             .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "domain": "new.edu",
//     });

//     let req = test::TestRequest::patch()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     assert_eq!(
//         json["data"]["school"]["name"], "My Uni",
//         "name should be unchanged"
//     );
//     assert_eq!(json["data"]["school"]["domain"], "new.edu");
// }

// #[sqlx::test]
// async fn update_school_no_fields_returns_400(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let result =
//         sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni', 'uni.edu') RETURNING id")
//             .fetch_one(&pool)
//             .await
//             .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({});

//     let req = test::TestRequest::patch()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 400, "empty update should return 400");
// }

// #[sqlx::test]
// async fn non_admin_cannot_update_school_returns_403(pool: PgPool) {
//     let student_id = seed_user_with_role(&pool, "student@test.edu", "student").await;
//     let student_user = make_user_model(student_id, "student@test.edu", "student");
//     let token = sign_access_token_for_user(&student_user);

//     let result =
//         sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni', 'uni.edu') RETURNING id")
//             .fetch_one(&pool)
//             .await
//             .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "Hacked Name",
//     });

//     let req = test::TestRequest::patch()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 403);
// }

// #[sqlx::test]
// async fn update_school_not_found_returns_404(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let body = serde_json::json!({
//         "name": "Ghost Uni",
//     });

//     let req = test::TestRequest::patch()
//         .uri("/api/v1/schools/9999")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 404);
// }

// #[sqlx::test]
// async fn update_school_duplicate_domain_returns_409(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     // Create two schools
//     sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni A', 'a.edu')")
//         .execute(&pool)
//         .await
//         .expect("seed school a");
//     let result_b =
//         sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni B', 'b.edu') RETURNING id")
//             .fetch_one(&pool)
//             .await
//             .expect("seed school b");
//     let school_b_id: i16 = result_b.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     // Try to change school B's domain to school A's domain
//     let body = serde_json::json!({
//         "domain": "a.edu",
//     });

//     let req = test::TestRequest::patch()
//         .uri(&format!("/api/v1/schools/{school_b_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .set_json(&body)
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 409, "duplicate domain should return 409");
// }

// // ===========================================================================
// // DELETE /api/v1/schools/{id} — delete school (admin-only)
// // ===========================================================================

// #[sqlx::test]
// async fn admin_can_delete_school(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let result = sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Delete Me', 'del.edu') RETURNING id",
//     )
//     .fetch_one(&pool)
//     .await
//     .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::delete()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 204, "successful delete should return 204");

//     // Confirm it's gone
//     let req2 = test::TestRequest::get()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .to_request();
//     let resp2 = test::call_service(&app, req2).await;
//     assert_eq!(resp2.status(), 404, "deleted school should return 404");
// }

// #[sqlx::test]
// async fn non_admin_cannot_delete_school_returns_403(pool: PgPool) {
//     let student_id = seed_user_with_role(&pool, "student@test.edu", "student").await;
//     let student_user = make_user_model(student_id, "student@test.edu", "student");
//     let token = sign_access_token_for_user(&student_user);

//     let result =
//         sqlx::query("INSERT INTO schools (name, domain) VALUES ('Uni', 'uni.edu') RETURNING id")
//             .fetch_one(&pool)
//             .await
//             .expect("seed school");
//     let school_id: i16 = result.get("id");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::delete()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 403);
// }

// #[sqlx::test]
// async fn delete_school_not_found_returns_404(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::delete()
//         .uri("/api/v1/schools/9999")
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 404);
// }

// #[sqlx::test]
// async fn delete_school_with_users_returns_400(pool: PgPool) {
//     let admin_id = seed_user_with_role(&pool, "admin@test.edu", "admin").await;
//     let admin_user = make_user_model(admin_id, "admin@test.edu", "admin");
//     let token = sign_access_token_for_user(&admin_user);

//     // Create a school that has users referencing it
//     let result = sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Has Users', 'hasusers.edu') RETURNING id",
//     )
//     .fetch_one(&pool)
//     .await
//     .expect("seed school");
//     let school_id: i16 = result.get("id");

//     // Create a user referencing that school
//     sqlx::query("INSERT INTO users (school_id, email, password_hash, display_name) VALUES ($1, 'user@hasusers.edu', 'hash', 'User')")
//         .bind(school_id)
//         .execute(&pool)
//         .await
//         .expect("seed user");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::delete()
//         .uri(&format!("/api/v1/schools/{school_id}"))
//         .insert_header(("Authorization", format!("Bearer {token}")))
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(
//         resp.status(),
//         400,
//         "deleting school with users should return 400 (FK violation)"
//     );
// }

// // ===========================================================================
// // GET /api/v1/schools?q=... — search schools (public)
// // ===========================================================================

// #[sqlx::test]
// async fn list_schools_search_filters_by_name(pool: PgPool) {
//     sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Alpha University', 'alpha.edu'), ('Beta College', 'beta.edu'), ('Gamma Institute', 'gamma.edu')",
//     )
//     .execute(&pool)
//     .await
//     .expect("seed schools");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get()
//         .uri("/api/v1/schools?q=alpha")
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     let schools = json["data"]["schools"].as_array().unwrap();
//     assert_eq!(
//         schools.len(),
//         1,
//         "search for 'alpha' should return 1 school"
//     );
//     assert_eq!(schools[0]["name"], "Alpha University");
// }

// #[sqlx::test]
// async fn list_schools_search_filters_by_domain(pool: PgPool) {
//     sqlx::query(
//         "INSERT INTO schools (name, domain) VALUES ('Uni A', 'alpha.edu'), ('Uni B', 'beta.edu')",
//     )
//     .execute(&pool)
//     .await
//     .expect("seed schools");

//     let state = test_state(pool);
//     let app = test::init_service(school_app(state)).await;

//     let req = test::TestRequest::get()
//         .uri("/api/v1/schools?q=beta.edu")
//         .to_request();
//     let resp = test::call_service(&app, req).await;
//     assert_eq!(resp.status(), 200);

//     let json: serde_json::Value = test::read_body_json(resp).await;
//     let schools = json["data"]["schools"].as_array().unwrap();
//     assert_eq!(
//         schools.len(),
//         1,
//         "search for 'beta.edu' should return 1 school"
//     );
//     assert_eq!(schools[0]["domain"], "beta.edu");
// }
