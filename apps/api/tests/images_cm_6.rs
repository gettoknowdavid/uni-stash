// apps/api/tests/images_cm_6.rs
//
// Epic 6 — Image Upload Pipeline integration tests.
//
// Covers CM-6.1 (presign), CM-6.2 (confirm), CM-6.3 (delete).
//
// Since the presign/confirm handlers call Backblaze B2 (unavailable in CI),
// these tests exercise the repo layer directly — ownership checks, position
// allocation, insert, and delete — which is where the real correctness
// guarantees live. The R2 client methods are tested via unit tests in
// core/clients/r2.rs.

use sqlx::PgPool;
use uni_stash_be::features::images::repo::ImagesRepo;

// const TEST_PRIVATE_PEM: &str = include_str!("fixtures/test_rsa_private.pem");
// const TEST_PUBLIC_PEM: &str = include_str!("fixtures/test_rsa_public.pem");

// fn test_config() -> Config {
//     Config {
//         database_url: "postgres://localhost:5432/uni_stash".into(),
//         jwt_private_key: TEST_PRIVATE_PEM.into(),
//         jwt_public_key: TEST_PUBLIC_PEM.into(),
//         resend_api_key: "".into(),
//         resend_base_url: "http://127.0.0.1:1".into(),
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

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

async fn seed_school(pool: &PgPool) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', 'test.edu') RETURNING id",
    )
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn seed_user(pool: &PgPool, school_id: i16, email: &str) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (school_id, email, password_hash, display_name)
         VALUES ($1, $2, 'hash', 'Test User') RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .fetch_one(pool)
    .await
    .expect("seed user")
}

async fn seed_category(pool: &PgPool, slug: &str) -> i16 {
    sqlx::query_scalar::<_, i16>(
        "INSERT INTO categories (slug, label) VALUES ($1, $1) RETURNING id",
    )
    .bind(slug)
    .fetch_one(pool)
    .await
    .expect("seed category")
}

async fn seed_listing(
    pool: &PgPool,
    seller_id: uuid::Uuid,
    category_id: i16,
    title: &str,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO listings (seller_id, category_id, title, description, price, condition)
         VALUES ($1, $2, $3, '', 10, 'used') RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .bind(title)
    .fetch_one(pool)
    .await
    .expect("seed listing")
}

async fn seed_image(pool: &PgPool, listing_id: uuid::Uuid, position: i16) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO images (listing_id, object_key, position)
         VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(listing_id)
    .bind(format!("listings/{listing_id}/{position}_test.jpg"))
    .bind(position)
    .fetch_one(pool)
    .await
    .expect("seed image")
}

// ===========================================================================
// CM-6.1 — check_presign_allowed
// ===========================================================================

#[sqlx::test]
async fn presign_returns_position_0_for_first_image(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);
    let position = repo.check_presign_allowed(listing, seller).await.unwrap();
    assert_eq!(position, 0, "first image should get position 0");
}

#[sqlx::test]
async fn presign_returns_position_1_after_position_0_taken(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    seed_image(&pool, listing, 0).await;

    let repo = ImagesRepo::new(pool);
    let position = repo.check_presign_allowed(listing, seller).await.unwrap();
    assert_eq!(position, 1, "second image should get position 1");
}

#[sqlx::test]
async fn presign_returns_position_2_after_positions_0_and_1_taken(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    seed_image(&pool, listing, 0).await;
    seed_image(&pool, listing, 1).await;

    let repo = ImagesRepo::new(pool);
    let position = repo.check_presign_allowed(listing, seller).await.unwrap();
    assert_eq!(position, 2, "third image should get position 2");
}

#[sqlx::test]
async fn presign_rejects_when_3_images_already_exist(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    seed_image(&pool, listing, 0).await;
    seed_image(&pool, listing, 1).await;
    seed_image(&pool, listing, 2).await;

    let repo = ImagesRepo::new(pool);
    let err = repo
        .check_presign_allowed(listing, seller)
        .await
        .unwrap_err();
    assert!(
        matches!(err, uni_stash_be::core::error::AppError::BadRequest(_)),
        "expected BadRequest for full listing, got: {err:?}"
    );
}

#[sqlx::test]
async fn presign_rejects_non_owner(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let other = seed_user(&pool, school, "other@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);
    let err = repo
        .check_presign_allowed(listing, other)
        .await
        .unwrap_err();
    assert!(
        matches!(err, uni_stash_be::core::error::AppError::Forbidden),
        "expected Forbidden for non-owner, got: {err:?}"
    );
}

#[sqlx::test]
async fn presign_rejects_nonexistent_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;

    let repo = ImagesRepo::new(pool);
    let fake_id = uuid::Uuid::new_v4();
    let err = repo
        .check_presign_allowed(fake_id, seller)
        .await
        .unwrap_err();
    assert!(
        matches!(err, uni_stash_be::core::error::AppError::NotFound(_)),
        "expected NotFound for nonexistent listing, got: {err:?}"
    );
}

// ===========================================================================
// CM-6.1 — Position allocation fills gaps
// ===========================================================================

#[sqlx::test]
async fn presign_fills_gap_when_middle_position_deleted(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    // Simulate: position 0 and 2 exist, position 1 was deleted
    seed_image(&pool, listing, 0).await;
    seed_image(&pool, listing, 2).await;

    let repo = ImagesRepo::new(pool);
    let position = repo.check_presign_allowed(listing, seller).await.unwrap();
    assert_eq!(position, 1, "should fill the gap at position 1");
}

// ===========================================================================
// CM-6.2 — confirm_image
// ===========================================================================

#[sqlx::test]
async fn confirm_image_inserts_with_correct_position(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);
    let key = format!("listings/{listing}/0_test.jpg");
    let confirmed = repo.confirm_image(listing, &key, seller).await.unwrap();

    assert_eq!(confirmed.listing_id, listing);
    assert_eq!(confirmed.object_key, key);
    assert_eq!(confirmed.position, 0);
    assert!(!confirmed.id.is_nil());
}

#[sqlx::test]
async fn confirm_image_rejects_non_owner(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let other = seed_user(&pool, school, "other@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);
    let key = format!("listings/{listing}/0_test.jpg");
    let err = repo.confirm_image(listing, &key, other).await.unwrap_err();
    assert!(matches!(
        err,
        uni_stash_be::core::error::AppError::Forbidden
    ));
}

#[sqlx::test]
async fn confirm_image_rejects_nonexistent_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;

    let repo = ImagesRepo::new(pool);
    let fake_id = uuid::Uuid::new_v4();
    let key = format!("listings/{fake_id}/0_test.jpg");
    let err = repo.confirm_image(fake_id, &key, seller).await.unwrap_err();
    assert!(matches!(
        err,
        uni_stash_be::core::error::AppError::NotFound(_)
    ));
}

#[sqlx::test]
async fn confirm_image_allocates_sequential_positions(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);

    let key0 = format!("listings/{listing}/0_first.jpg");
    let c0 = repo.confirm_image(listing, &key0, seller).await.unwrap();
    assert_eq!(c0.position, 0);

    let key1 = format!("listings/{listing}/1_second.jpg");
    let c1 = repo.confirm_image(listing, &key1, seller).await.unwrap();
    assert_eq!(c1.position, 1);

    let key2 = format!("listings/{listing}/2_third.jpg");
    let c2 = repo.confirm_image(listing, &key2, seller).await.unwrap();
    assert_eq!(c2.position, 2);
}

#[sqlx::test]
async fn confirm_image_rejects_when_full(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);

    // Fill all 3 positions
    for pos in 0..3 {
        let key = format!("listings/{listing}/{pos}_test.jpg");
        repo.confirm_image(listing, &key, seller).await.unwrap();
    }

    // 4th confirm should fail
    let key = format!("listings/{listing}/0_fourth.jpg");
    let err = repo.confirm_image(listing, &key, seller).await.unwrap_err();
    assert!(
        matches!(err, uni_stash_be::core::error::AppError::BadRequest(_)),
        "expected BadRequest when listing is full, got: {err:?}"
    );
}

// ===========================================================================
// CM-6.3 — delete_image
// ===========================================================================

#[sqlx::test]
async fn delete_image_removes_row_and_returns_object_key(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool.clone());
    let key = format!("listings/{listing}/0_test.jpg");
    let confirmed = repo.confirm_image(listing, &key, seller).await.unwrap();

    let deleted_key = repo.delete_image(confirmed.id, seller).await.unwrap();
    assert_eq!(deleted_key, key);

    // Verify the row is gone
    let count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM images WHERE listing_id = $1")
        .bind(listing)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0, "image row must be deleted");
}

#[sqlx::test]
async fn delete_image_rejects_non_owner(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let other = seed_user(&pool, school, "other@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);
    let key = format!("listings/{listing}/0_test.jpg");
    let confirmed = repo.confirm_image(listing, &key, seller).await.unwrap();

    let err = repo.delete_image(confirmed.id, other).await.unwrap_err();
    assert!(matches!(
        err,
        uni_stash_be::core::error::AppError::Forbidden
    ));
}

#[sqlx::test]
async fn delete_image_rejects_nonexistent(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;

    let repo = ImagesRepo::new(pool);
    let fake_id = uuid::Uuid::new_v4();
    let err = repo.delete_image(fake_id, seller).await.unwrap_err();
    assert!(matches!(
        err,
        uni_stash_be::core::error::AppError::NotFound(_)
    ));
}

#[sqlx::test]
async fn delete_image_allows_reusing_position(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool);

    // Add image at position 0
    let key0 = format!("listings/{listing}/0_first.jpg");
    let c0 = repo.confirm_image(listing, &key0, seller).await.unwrap();
    assert_eq!(c0.position, 0);

    // Delete it
    repo.delete_image(c0.id, seller).await.unwrap();

    // New image should get position 0 again (fills the gap)
    let key0b = format!("listings/{listing}/0_second.jpg");
    let c0b = repo.confirm_image(listing, &key0b, seller).await.unwrap();
    assert_eq!(
        c0b.position, 0,
        "position 0 should be reusable after delete"
    );
}

// ===========================================================================
// CM-6.2 + CM-6.3 — Full lifecycle: add 3, delete middle, add fills gap
// ===========================================================================

#[sqlx::test]
async fn full_lifecycle_add_delete_readd(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    let repo = ImagesRepo::new(pool.clone());

    // Add 3 images
    let mut ids = Vec::new();
    for pos in 0..3 {
        let key = format!("listings/{listing}/{pos}_lifecycle.jpg");
        let c = repo.confirm_image(listing, &key, seller).await.unwrap();
        assert_eq!(c.position, pos);
        ids.push(c);
    }

    // Listing is full
    assert!(repo.check_presign_allowed(listing, seller).await.is_err());

    // Delete the middle one (position 1)
    let deleted_key = repo.delete_image(ids[1].id, seller).await.unwrap();
    assert!(deleted_key.contains("/1_"));

    // Now we can add again — should fill position 1
    let key_new = format!("listings/{listing}/1_replacement.jpg");
    let c_new = repo.confirm_image(listing, &key_new, seller).await.unwrap();
    assert_eq!(c_new.position, 1, "should fill the gap at position 1");

    // Still have 3 images (0, 1, 2)
    let count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM images WHERE listing_id = $1")
        .bind(listing)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 3);
}

// ===========================================================================
// CM-6.2 — max_three_images constraint (DB-level)
// ===========================================================================

#[sqlx::test]
async fn db_constraint_rejects_4th_image_at_same_position(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu").await;
    let cat = seed_category(&pool, "textbooks").await;
    let listing = seed_listing(&pool, seller, cat, "Book").await;

    // Insert 3 images at positions 0, 1, 2
    for pos in 0..3 {
        sqlx::query("INSERT INTO images (listing_id, object_key, position) VALUES ($1, $2, $3)")
            .bind(listing)
            .bind(format!("key_{pos}"))
            .bind(pos)
            .execute(&pool)
            .await
            .unwrap();
    }

    // Attempt to insert a 4th at position 0 — must violate max_three_images
    let err =
        sqlx::query("INSERT INTO images (listing_id, object_key, position) VALUES ($1, $2, $3)")
            .bind(listing)
            .bind("key_duplicate")
            .bind(0i16)
            .execute(&pool)
            .await;

    assert!(
        err.is_err(),
        "DB must reject 4th image at same position via max_three_images constraint"
    );
}
