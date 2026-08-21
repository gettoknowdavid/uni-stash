use sqlx::PgPool;
use uni_stash_be::core::error::AppError;
use uni_stash_be::features::listings::state_machine;

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
async fn seed_category(p: &PgPool) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ('x', 'X') RETURNING id",
    )
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
async fn seed_reserved(p: &PgPool, seller: uuid::Uuid, buyer: uuid::Uuid, cat: i16) -> uuid::Uuid {
    let id = seed_listing(p, seller, cat, "active").await;
    state_machine::reserve_listing(p, id, buyer).await.unwrap();
    id
}

#[derive(sqlx::FromRow)]
struct Ls {
    status: String,
    reserved_by: Option<uuid::Uuid>,
    // reserved_at: Option<bool>,
}

async fn get_state(p: &PgPool, id: uuid::Uuid) -> Ls {
    sqlx::query_as::<_, Ls>(
        "SELECT status, reserved_by, (reserved_at IS NOT NULL) as reserved_at FROM listings WHERE id = $1",
    ).bind(id).fetch_one(p).await.unwrap()
}

// ===========================================================================
// Mark sold
// ===========================================================================

#[sqlx::test]
async fn seller_can_mark_reserved_listing_sold(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let result = state_machine::mark_sold(&pool, id, seller).await;
    assert!(result.is_ok());
    let s = get_state(&pool, id).await;
    assert_eq!(s.status, "sold");
}

#[sqlx::test]
async fn buyer_cannot_mark_sold(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let result = state_machine::mark_sold(&pool, id, buyer).await;
    assert!(matches!(result, Err(AppError::Forbidden)));
}

#[sqlx::test]
async fn marking_active_listing_sold_returns_conflict(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    let result = state_machine::mark_sold(&pool, id, seller).await;
    assert!(matches!(result, Err(AppError::Conflict(_))));
}

#[sqlx::test]
async fn marking_already_sold_returns_conflict(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;
    state_machine::mark_sold(&pool, id, seller).await.unwrap();

    let result = state_machine::mark_sold(&pool, id, seller).await;
    assert!(matches!(result, Err(AppError::Conflict(_))));
}

#[sqlx::test]
async fn mark_sold_nonexistent_returns_404(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let result = state_machine::mark_sold(&pool, uuid::Uuid::new_v4(), seller).await;
    assert!(matches!(result, Err(AppError::NotFound(_))));
}

// ===========================================================================
// Unreserve
// ===========================================================================

#[sqlx::test]
async fn seller_can_unreserve(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let result = state_machine::unreserve(&pool, id, seller).await;
    assert!(result.is_ok());
    let s = get_state(&pool, id).await;
    assert_eq!(s.status, "active");
    assert!(s.reserved_by.is_none());
}

#[sqlx::test]
async fn reserving_buyer_can_unreserve(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let result = state_machine::unreserve(&pool, id, buyer).await;
    assert!(result.is_ok());
}

#[sqlx::test]
async fn unrelated_user_cannot_unreserve(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let stranger = seed_user(&pool, school, "x@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let result = state_machine::unreserve(&pool, id, stranger).await;
    assert!(matches!(result, Err(AppError::Forbidden)));
}

#[sqlx::test]
async fn unreserving_active_listing_returns_conflict(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_listing(&pool, seller, cat, "active").await;

    let result = state_machine::unreserve(&pool, id, seller).await;
    assert!(matches!(result, Err(AppError::Conflict(_))));
}

#[sqlx::test]
async fn unreserved_listing_can_be_reserved_again(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let b1 = seed_user(&pool, school, "b1@test.edu").await;
    let b2 = seed_user(&pool, school, "b2@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, b1, cat).await;

    // Unreserve
    state_machine::unreserve(&pool, id, seller).await.unwrap();
    // Reserve by different buyer
    let result = state_machine::reserve_listing(&pool, id, b2).await;
    assert!(result.is_ok());
    let s = get_state(&pool, id).await;
    assert_eq!(s.reserved_by, Some(b2));
}

#[sqlx::test]
async fn concurrent_mark_sold_and_unresolve_resolve_deterministically(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = seed_reserved(&pool, seller, buyer, cat).await;

    let (r1, r2) = tokio::join!(
        state_machine::mark_sold(&pool, id, seller),
        state_machine::unreserve(&pool, id, seller),
    );

    let successes = [r1.is_ok(), r2.is_ok()].iter().filter(|&&x| x).count();
    assert_eq!(successes, 1, "exactly one operation must succeed");

    let s = get_state(&pool, id).await;
    // Final state must be internally consistent
    assert!(
        s.status == "sold" || (s.status == "active" && s.reserved_by.is_none()),
        "final state must be fully sold or fully active with cleared fields, got: {:?}",
        s.status,
    );
}
