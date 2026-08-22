// apps/api/tests/auth_token_cleanup_cm_3_10.rs
//
// CM-3.10 — Background cleanup of expired / old revoked refresh tokens.
//
//   AC 1 — Expired refresh tokens (expires_at < now) are deleted.
//   AC 2 — Revoked tokens are retained for a configurable grace period,
//          then deleted (prevents unbounded table growth while preserving
//          the CM-3.8 reuse-detection window).
//   AC 3 — Non-expired, non-revoked tokens are never touched by cleanup.
//   AC 4 — Cleanup is idempotent.

use sqlx::PgPool;
use uuid::Uuid;

use uni_stash_be::core::auth::password;
use uni_stash_be::core::auth::refresh_token;
use uni_stash_be::features::auth::repo::AuthRepo;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async fn seed_school(pool: &PgPool, domain: &str) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', $1) RETURNING id",
    )
    .bind(domain)
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn insert_user(pool: &PgPool, school_id: i16, email: &str) -> Uuid {
    let hash = password::hash_password("correct horse battery staple").expect("hash");
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name)
         VALUES ($1, $2, $3, 'Test User') RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(&hash)
    .fetch_one(pool)
    .await
    .expect("insert user")
}

/// Insert a token that expires `interval` from now (e.g. "21 days").
async fn insert_token_expiring_in(pool: &PgPool, user_id: Uuid, interval: &str) -> String {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, $3, now() + $4::interval)",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(Uuid::new_v4())
    .bind(interval)
    .execute(pool)
    .await
    .expect("insert token");
    plain
}

/// Insert a token that expired `interval` ago (e.g. "1 day").
async fn insert_expired_token(pool: &PgPool, user_id: Uuid, interval: &str) -> String {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, $3, now() - $4::interval)",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(Uuid::new_v4())
    .bind(interval)
    .execute(pool)
    .await
    .expect("insert expired token");
    plain
}

/// Insert a revoked token with `revoked_at = now() - $1 interval`.
async fn insert_revoked_token(pool: &PgPool, user_id: Uuid, revoked_ago: &str) -> String {
    let plain = refresh_token::generate_refresh_token_plain();
    let hash = refresh_token::hash_refresh_token(&plain);
    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, revoked, revoked_at, expires_at)
         VALUES ($1, $2, $3, true, now() - $4::interval, now() + interval '21 days')",
    )
    .bind(user_id)
    .bind(&hash)
    .bind(Uuid::new_v4())
    .bind(revoked_ago)
    .execute(pool)
    .await
    .expect("insert revoked token");
    plain
}

async fn count_tokens(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM refresh_tokens")
        .fetch_one(pool)
        .await
        .expect("count tokens")
}

async fn count_expired_tokens(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM refresh_tokens WHERE expires_at < now()")
        .fetch_one(pool)
        .await
        .expect("count expired tokens")
}

// ===========================================================================
// AC 1 — Expired refresh tokens are deleted
// ===========================================================================

#[sqlx::test]
async fn cleanup_deletes_expired_tokens(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "alice@test.edu").await;

    insert_expired_token(&pool, user_id, "1 day").await;
    insert_expired_token(&pool, user_id, "7 days").await;
    insert_expired_token(&pool, user_id, "1 hour").await;
    insert_token_expiring_in(&pool, user_id, "21 days").await;
    insert_token_expiring_in(&pool, user_id, "10 days").await;

    assert_eq!(count_tokens(&pool).await, 5);
    assert_eq!(count_expired_tokens(&pool).await, 3);

    let repo = AuthRepo::new(pool.clone());
    let deleted = repo.cleanup_expired_refresh_tokens().await.unwrap();

    assert_eq!(deleted, 3, "must delete exactly the 3 expired tokens");
    assert_eq!(count_tokens(&pool).await, 2, "2 valid tokens must remain");
    assert_eq!(
        count_expired_tokens(&pool).await,
        0,
        "no expired tokens left"
    );
}

// ===========================================================================
// AC 2 — Old revoked tokens are deleted after retention period
// ===========================================================================

#[sqlx::test]
async fn cleanup_deletes_old_revoked_tokens(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "bob@test.edu").await;

    insert_revoked_token(&pool, user_id, "48 hours").await; // old → delete
    insert_revoked_token(&pool, user_id, "72 hours").await; // old → delete
    insert_revoked_token(&pool, user_id, "1 hour").await; // recent → keep
    insert_token_expiring_in(&pool, user_id, "21 days").await; // valid → keep

    assert_eq!(count_tokens(&pool).await, 4);

    let repo = AuthRepo::new(pool.clone());
    let deleted = repo.cleanup_old_revoked_tokens(86400).await.unwrap(); // 24h

    assert_eq!(deleted, 2, "must delete the 2 old revoked tokens");
    assert_eq!(
        count_tokens(&pool).await,
        2,
        "recent revoked + valid remain"
    );
}

// ===========================================================================
// AC 3 — Non-expired, non-revoked tokens are never touched
// ===========================================================================

#[sqlx::test]
async fn cleanup_preserves_valid_tokens(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "carol@test.edu").await;

    insert_token_expiring_in(&pool, user_id, "21 days").await;
    insert_token_expiring_in(&pool, user_id, "10 days").await;
    insert_token_expiring_in(&pool, user_id, "1 day").await;

    assert_eq!(count_tokens(&pool).await, 3);

    let repo = AuthRepo::new(pool.clone());
    let d1 = repo.cleanup_expired_refresh_tokens().await.unwrap();
    let d2 = repo.cleanup_old_revoked_tokens(86400).await.unwrap();

    assert_eq!(d1, 0);
    assert_eq!(d2, 0);
    assert_eq!(count_tokens(&pool).await, 3, "all 3 tokens must remain");
}

// ===========================================================================
// AC 4 — Cleanup is idempotent
// ===========================================================================

#[sqlx::test]
async fn cleanup_is_idempotent(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "dave@test.edu").await;

    insert_expired_token(&pool, user_id, "1 day").await;
    insert_token_expiring_in(&pool, user_id, "21 days").await;

    let repo = AuthRepo::new(pool.clone());

    let d1 = repo.cleanup_expired_refresh_tokens().await.unwrap();
    assert_eq!(d1, 1);

    let d2 = repo.cleanup_expired_refresh_tokens().await.unwrap();
    assert_eq!(d2, 0, "second cleanup must delete nothing");

    assert_eq!(count_tokens(&pool).await, 1);
}

// ===========================================================================
// AC 5 — Mixed scenario: expired + revoked + valid
// ===========================================================================

#[sqlx::test]
async fn cleanup_handles_mixed_scenario(pool: PgPool) {
    let school_id = seed_school(&pool, "test.edu").await;
    let user_id = insert_user(&pool, school_id, "eve@test.edu").await;

    insert_expired_token(&pool, user_id, "3 days").await; // expired → delete
    insert_revoked_token(&pool, user_id, "48 hours").await; // old revoked → delete
    insert_revoked_token(&pool, user_id, "1 hour").await; // recent revoked → keep
    insert_token_expiring_in(&pool, user_id, "21 days").await; // valid → keep

    assert_eq!(count_tokens(&pool).await, 4);

    let repo = AuthRepo::new(pool.clone());
    repo.cleanup_expired_refresh_tokens().await.unwrap();
    repo.cleanup_old_revoked_tokens(86400).await.unwrap();

    assert_eq!(
        count_tokens(&pool).await,
        2,
        "old expired + old revoked deleted; recent revoked + valid remain"
    );
}
