use sqlx::PgPool;
use uni_stash_be::features::listings::{repo::ListingsRepo, state_machine};

async fn seed_school(p: &PgPool) -> i16 {
    sqlx::query_scalar("INSERT INTO schools (name, domain) VALUES ('T', 't.edu') RETURNING id")
        .fetch_one(p).await.unwrap()
}
async fn seed_user(p: &PgPool, s: i16, e: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name) VALUES ($1, $2, 'h', 'U') RETURNING id",
    ).bind(s).bind(e).fetch_one(p).await.unwrap()
}
async fn seed_category(p: &PgPool) -> i16 {
    sqlx::query_scalar::<_, i16>("INSERT INTO categories (slug, label) VALUES ('x', 'X') RETURNING id")
        .fetch_one(p).await.unwrap()
}

async fn create_and_reserve(p: &PgPool, seller: uuid::Uuid, buyer: uuid::Uuid, cat: i16) -> uuid::Uuid {
    let id = sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Item', '', 'new', 'active') RETURNING id",
    ).bind(seller).bind(cat).fetch_one(p).await.unwrap();
    state_machine::reserve_listing(p, id, buyer).await.unwrap();
    id
}

#[derive(sqlx::FromRow)]
struct Ls { status: String, reserved_by: Option<uuid::Uuid> }

async fn get_state(p: &PgPool, id: uuid::Uuid) -> Ls {
    sqlx::query_as::<_, Ls>("SELECT status, reserved_by FROM listings WHERE id = $1")
        .bind(id).fetch_one(p).await.unwrap()
}

// ===========================================================================

#[sqlx::test]
async fn finds_reservations_older_than_48_hours(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = create_and_reserve(&pool, seller, buyer, cat).await;

    // Make the reservation appear 49 hours old
    sqlx::query("UPDATE listings SET reserved_at = now() - interval '49 hours' WHERE id = $1")
        .bind(id).execute(&pool).await.unwrap();

    let repo = ListingsRepo::new(pool);
    let ids = repo.find_stale_reservation_ids(48).await.unwrap();
    assert!(ids.contains(&id));
}

#[sqlx::test]
async fn excludes_reservations_within_48_hours(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = create_and_reserve(&pool, seller, buyer, cat).await;

    let repo = ListingsRepo::new(pool);
    let ids = repo.find_stale_reservation_ids(48).await.unwrap();
    assert!(!ids.contains(&id), "fresh reservation must not be stale");
}

#[sqlx::test]
async fn excludes_active_and_sold_listings(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let cat = seed_category(&pool).await;

    // Active listing
    let active_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Active', '', 'new', 'active') RETURNING id",
    ).bind(seller).bind(cat).fetch_one(&pool).await.unwrap();

    // Sold listing
    let sold_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Sold', '', 'new', 'sold') RETURNING id",
    ).bind(seller).bind(cat).fetch_one(&pool).await.unwrap();

    let repo = ListingsRepo::new(pool);
    let ids = repo.find_stale_reservation_ids(48).await.unwrap();
    assert!(!ids.contains(&active_id));
    assert!(!ids.contains(&sold_id));
}

#[sqlx::test]
async fn stale_reservation_is_auto_unreserved(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = create_and_reserve(&pool, seller, buyer, cat).await;

    // Age the reservation
    sqlx::query("UPDATE listings SET reserved_at = now() - interval '49 hours' WHERE id = $1")
        .bind(id).execute(&pool).await.unwrap();

    // Simulate the job logic
    let repo = ListingsRepo::new(pool.clone());
    let stale_ids = repo.find_stale_reservation_ids(48).await.unwrap();
    for lid in stale_ids {
        let _ = state_machine::unreserve_system(&pool, lid).await;
    }

    let s = get_state(&pool, id).await;
    assert_eq!(s.status, "active");
    assert!(s.reserved_by.is_none());
}

#[sqlx::test]
async fn fresh_reservation_is_untouched(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = create_and_reserve(&pool, seller, buyer, cat).await;

    let repo = ListingsRepo::new(pool.clone());
    let stale_ids = repo.find_stale_reservation_ids(48).await.unwrap();
    assert!(stale_ids.is_empty());

    let s = get_state(&pool, id).await;
    assert_eq!(s.status, "reserved");
}

#[sqlx::test]
async fn auto_unreserve_does_not_race_concurrent_mark_sold(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "s@test.edu").await;
    let buyer = seed_user(&pool, school, "b@test.edu").await;
    let cat = seed_category(&pool).await;
    let id = create_and_reserve(&pool, seller, buyer, cat).await;

    // Age it
    sqlx::query("UPDATE listings SET reserved_at = now() - interval '49 hours' WHERE id = $1")
        .bind(id).execute(&pool).await.unwrap();

    let (r1, r2) = tokio::join!(
        state_machine::unreserve_system(&pool, id),
        state_machine::mark_sold(&pool, id, seller),
    );

    let successes = [r1.is_ok(), r2.is_ok()].iter().filter(|&&x| x).count();
    assert_eq!(successes, 1);

    let s = get_state(&pool, id).await;
    assert!(
        s.status == "sold" || (s.status == "active" && s.reserved_by.is_none()),
        "final state must be internally consistent, got: {:?}",
        s.status,
    );
}
