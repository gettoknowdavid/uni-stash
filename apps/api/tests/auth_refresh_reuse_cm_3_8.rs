// apps/api/tests/auth_refresh_reuse_cm_3_8.rs
//
// CM-3.8 — Refresh-token reuse detection & family revocation.
//
//   Scenario (a) — Legitimate retry within grace window:
//     Rotate A → B, then re-present A within the grace window → succeeds,
//     returns a rotation of the CURRENT valid token (B), family intact.
//
//   Scenario (b) — Compromise outside grace window:
//     Rotate A → B, backdate revoked_at past the grace window, re-present A
//     → 401, and B is now also revoked (family nuked).
//
//   Follow-up — After family revocation:
//     Presenting B (previously valid, now force-revoked) → 401.
//
//   Design note — Access tokens already issued during the family's lifetime
//   are NOT tracked or blacklisted.  This is intentional: the stateless-JWT
//   design means they simply expire on their own 15-minute TTL (CM-3.2).
//   Revoking a family only prevents *new* access tokens from being minted
//   via refresh rotation.  See CM-3.10 for the future background cleanup job.

use actix_web::{App, test, web};
use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::password;
use uni_stash_be::core::auth::refresh_token;
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::state::AppState;
use uni_stash_be::features::auth::repo::AuthRepo;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

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
    let config = test_config();
    let db = Db { pool };
    web::Data::new(AppState::new(&config, db).expect("AppState"))
}

async fn seed_school(pool: &PgPool, domain: &str) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', $1) RETURNING id",
    )
    .bind(domain)
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn insert_user(pool: &PgPool, school_id: i16, email: &str, email_verified: bool) -> Uuid {
    let hash = password::hash_password("correct horse battery staple").expect("hash password");
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name, email_verified)
         VALUES ($1, $2, $3, 'Test User', $4)
         RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(&hash)
    .bind(email_verified)
    .fetch_one(pool)
    .await
    .expect("insert user")
}

/// Insert a refresh token row directly and return `(plain, row_id)`.
async fn insert_refresh_token(pool: &PgPool, user_id: Uuid, family_id: Uuid) -> (String, Uuid) {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    let id = sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, $3, now() + interval '21 days')
         RETURNING id",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(family_id)
    .fetch_one(pool)
    .await
    .expect("insert refresh token");
    (plain, id)
}

// async fn find_token_by_id(pool: &PgPool, token_id: Uuid) -> RefreshToken {
//     sqlx::query_as!(RefreshToken, "SELECT * FROM refresh_tokens WHERE id = $1", token_id)
//         .fetch_one(pool)
//         .await
//         .expect("find token")
// }

async fn call_refresh(
    state: &web::Data<AppState>,
    refresh_token: &str,
) -> actix_web::dev::ServiceResponse {
    let app = test::init_service(App::new().app_data(state.clone()).route(
        "/api/v1/auth/refresh",
        web::post().to(uni_stash_be::features::auth::handlers::refresh),
    ))
    .await;

    let req = test::TestRequest::post()
        .uri("/api/v1/auth/refresh")
        .set_json(serde_json::json!({ "refresh_token": refresh_token }))
        .to_request();

    test::call_service(&app, req).await
}

/// Helper: rotate token A → B via the refresh handler, return B's plain text.
async fn rotate_once(state: &web::Data<AppState>, plain_a: &str) -> String {
    let resp = call_refresh(state, plain_a).await;
    assert_eq!(resp.status(), 200, "rotation must succeed");
    let json: serde_json::Value = test::read_body_json(resp).await;
    json["data"]["refresh_token"]
        .as_str()
        .expect("new refresh_token")
        .to_string()
}

// ===========================================================================
// Scenario (a) — Legitimate retry within grace window
// ===========================================================================

#[sqlx::test]
async fn reuse_within_grace_rotates_from_current_valid_token(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "alice@test.edu", true).await;
    let family_id = Uuid::new_v4();
    let (plain_a, _id_a) = insert_refresh_token(&pool, user_id, family_id).await;

    let state = test_state(pool.clone());

    // Step 1: Rotate A → B (happy path).
    let plain_b = rotate_once(&state, &plain_a).await;

    // Step 2: Re-present A within the grace window (< 5 seconds).
    //   This simulates a network retry where the client's second request
    //   arrives before the first response reaches it.
    let resp = call_refresh(&state, &plain_a).await;
    assert_eq!(resp.status(), 200, "reuse within grace window must succeed");
    let json: serde_json::Value = test::read_body_json(resp).await;
    let plain_c = json["data"]["refresh_token"]
        .as_str()
        .expect("refresh_token");

    // C must differ from both A and B — it's a rotation of B.
    assert_ne!(plain_c, plain_a, "C must differ from A");
    assert_ne!(plain_c, plain_b, "C must differ from B");

    // Family must still be intact — all three tokens share family_id.
    let families: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT family_id FROM refresh_tokens WHERE user_id = $1")
            .bind(user_id)
            .fetch_all(&pool)
            .await
            .expect("query families");
    assert_eq!(families.len(), 1, "all tokens must share one family");
    assert_eq!(families[0], family_id);

    // No error, no family revocation — just a smooth retry.
}

// ===========================================================================
// Scenario (b) — Compromise outside grace window
// ===========================================================================

#[sqlx::test]
async fn reuse_outside_grace_revokes_entire_family(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "bob@test.edu", true).await;
    let family_id = Uuid::new_v4();
    let (plain_a, id_a) = insert_refresh_token(&pool, user_id, family_id).await;

    let state = test_state(pool.clone());

    // Step 1: Rotate A → B (happy path).
    let plain_b = rotate_once(&state, &plain_a).await;

    // Step 2: Backdate A's revoked_at past the grace window (5 seconds).
    //   This simulates a scenario where an attacker obtained token A,
    //   the legitimate user rotated to B much earlier, and now the
    //   attacker tries to use A.
    sqlx::query(
        "UPDATE refresh_tokens SET revoked_at = now() - interval '60 seconds' WHERE id = $1",
    )
    .bind(id_a)
    .execute(&pool)
    .await
    .expect("backdate revoked_at");

    // Step 3: Re-present A → must fail with 401.
    let resp = call_refresh(&state, &plain_a).await;
    assert_eq!(resp.status(), 401, "reuse outside grace must fail");
    let json: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(json["error"]["code"], "unauthorized");

    // Step 4: B must now also be revoked (family nuked), even though
    //   B was never directly presented to the reuse-detection path.
    let auth_repo = AuthRepo::new(pool.clone());
    let hash_b = refresh_token::hash_refresh_token(&plain_b);
    let row_b = auth_repo
        .find_refresh_token_by_hash(&hash_b)
        .await
        .expect("query")
        .expect("B must still exist in DB");
    assert!(row_b.revoked, "B must be revoked after family-wide nuke");
    assert!(
        row_b.revoked_at.is_some(),
        "B's revoked_at must be set after family-wide nuke"
    );
}

// ===========================================================================
// Follow-up — After family revocation, B also fails
// ===========================================================================

#[sqlx::test]
async fn after_family_revocation_presenting_b_returns_401(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "carol@test.edu", true).await;
    let family_id = Uuid::new_v4();
    let (plain_a, id_a) = insert_refresh_token(&pool, user_id, family_id).await;

    let state = test_state(pool.clone());

    // Rotate A → B.
    let plain_b = rotate_once(&state, &plain_a).await;

    // Backdate A's revoked_at to trigger family revocation on reuse.
    sqlx::query(
        "UPDATE refresh_tokens SET revoked_at = now() - interval '60 seconds' WHERE id = $1",
    )
    .bind(id_a)
    .execute(&pool)
    .await
    .expect("backdate revoked_at");

    // Re-present A → family revocation fires.
    let resp1 = call_refresh(&state, &plain_a).await;
    assert_eq!(resp1.status(), 401);

    // Now present B → must also fail (it was force-revoked by the family nuke).
    let resp2 = call_refresh(&state, &plain_b).await;
    assert_eq!(
        resp2.status(),
        401,
        "B must be rejected after family revocation"
    );
    let json: serde_json::Value = test::read_body_json(resp2).await;
    assert_eq!(json["error"]["code"], "unauthorized");
}

// ===========================================================================
// Note — Access tokens are NOT blacklisted (stateless JWT design)
// ===========================================================================
// Access tokens already issued during the family's lifetime are intentionally
// NOT tracked or revoked by this flow.  The stateless-JWT design means they
// simply expire on their own 15-minute TTL (CM-3.2).  Family revocation only
// prevents *new* access tokens from being minted via refresh rotation.  A
// future CM-3.10 background job will clean up expired refresh token rows.
