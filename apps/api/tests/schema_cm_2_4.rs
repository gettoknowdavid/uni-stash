// apps/api/tests/schema_cm_2_4.rs
//
// CM-2.4 — Constraint & cascade verification test suite.
//
// Exercises every FK cascade rule and CHECK/UNIQUE constraint from TRD §3 in
// one place so schema regressions are caught automatically. Every test runs
// against its own ephemeral Postgres database via `#[sqlx::test]` (the macro
// creates a throwaway DB per test and applies the `migrations/` in this crate
// automatically) — the same approach CI will use in Epic 13.
//
// The one deliberate non-cascade in the schema — `listings.reserved_by` — is
// covered by `deleting_reserver_clears_reserved_by_without_cascading_listing`;
// everything else must cascade on parent delete.

use sqlx::PgPool;
use sqlx::types::Uuid;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

async fn seed_school(pool: &PgPool) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO schools (name, domain) VALUES ('Test University', 'test.edu') RETURNING id",
    )
    .fetch_one(pool)
    .await
    .expect("seed school")
}

async fn seed_user(pool: &PgPool, school_id: i16, email: &str, display_name: &str) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO users (school_id, email, password_hash, display_name)
         VALUES ($1, $2, 'not-a-real-hash', $3) RETURNING id",
    )
    .bind(school_id)
    .bind(email)
    .bind(display_name)
    .fetch_one(pool)
    .await
    .expect("seed user")
}

async fn seed_category(pool: &PgPool) -> i16 {
    sqlx::query_scalar(
        "INSERT INTO categories (slug, label) VALUES ('textbooks', 'Textbooks') RETURNING id",
    )
    .fetch_one(pool)
    .await
    .expect("seed category")
}

async fn seed_listing(pool: &PgPool, seller_id: Uuid, category_id: i16) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status)
         VALUES ($1, $2, 'Calculus textbook', 'Second-hand calculus book', 'used', 'active')
         RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .fetch_one(pool)
    .await
    .expect("seed listing")
}

async fn seed_reserved_listing(
    pool: &PgPool,
    seller_id: Uuid,
    reserver_id: Uuid,
    category_id: i16,
) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO listings (seller_id, category_id, title, description, condition, status, reserved_by, reserved_at)
         VALUES ($1, $2, 'Calculus textbook', 'Reserved book', 'used', 'reserved', $3, now())
         RETURNING id",
    )
    .bind(seller_id)
    .bind(category_id)
    .bind(reserver_id)
    .fetch_one(pool)
    .await
    .expect("seed reserved listing")
}

async fn seed_image(pool: &PgPool, listing_id: Uuid, position: i16) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO images (listing_id, object_key, position) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(listing_id)
    .bind(format!("listing/{listing_id}/img-{position}.jpg"))
    .bind(position)
    .fetch_one(pool)
    .await
    .expect("seed image")
}

async fn seed_chat(pool: &PgPool, listing_id: Uuid, buyer_id: Uuid, seller_id: Uuid) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO chats (listing_id, buyer_id, seller_id) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(listing_id)
    .bind(buyer_id)
    .bind(seller_id)
    .fetch_one(pool)
    .await
    .expect("seed chat")
}

async fn seed_message(pool: &PgPool, chat_id: Uuid, sender_id: Uuid, body: &str) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO messages (chat_id, sender_id, body) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(chat_id)
    .bind(sender_id)
    .bind(body)
    .fetch_one(pool)
    .await
    .expect("seed message")
}

async fn seed_refresh_token(pool: &PgPool, user_id: Uuid, token_hash: &str) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, gen_random_uuid(), now() + interval '7 days') RETURNING id",
    )
    .bind(user_id)
    .bind(token_hash)
    .fetch_one(pool)
    .await
    .expect("seed refresh token")
}

async fn seed_report(
    pool: &PgPool,
    reporter_id: Uuid,
    listing_id: Option<Uuid>,
    reported_user_id: Option<Uuid>,
) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO reports (reporter_id, listing_id, reported_user_id, reason)
         VALUES ($1, $2, $3, 'spam') RETURNING id",
    )
    .bind(reporter_id)
    .bind(listing_id)
    .bind(reported_user_id)
    .fetch_one(pool)
    .await
    .expect("seed report")
}

/// Whether a row with the given UUID `id` still exists in `table`.
///
/// `table` is always one of a fixed set of hardcoded identifiers passed by the
/// call sites below, so the interpolated SQL is audited as injection-safe.
async fn uuid_row_exists(pool: &PgPool, table: &str, id: Uuid) -> bool {
    let sql = format!("SELECT EXISTS(SELECT 1 FROM {table} WHERE id = $1)");
    sqlx::query_scalar::<_, bool>(sqlx::AssertSqlSafe(sql))
        .bind(id)
        .fetch_one(pool)
        .await
        .expect("check row existence")
}

/// Downcast an `sqlx::Error` to the database-level error, panicking otherwise.
fn db_error(err: &sqlx::Error) -> &dyn sqlx::error::DatabaseError {
    err.as_database_error()
        .expect("expected a database-level error")
}

// ---------------------------------------------------------------------------
// FK cascade behavior (TRD §3 FK summary: all ON DELETE CASCADE except
// `listings.reserved_by`, which is nulled-not-cascaded)
// ---------------------------------------------------------------------------

#[sqlx::test]
async fn deleting_reserver_clears_reserved_by_without_cascading_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let reserver = seed_user(&pool, school, "reserver@test.edu", "Reserver").await;
    let category = seed_category(&pool).await;
    let listing = seed_reserved_listing(&pool, seller, reserver, category).await;

    // `reserved_by` is deliberately NOT ON DELETE CASCADE (nor SET NULL):
    // silently wiping the reservation — or nulling it out while `status` is
    // still 'reserved' — would corrupt the row. The DB refuses the raw delete
    // with a foreign_key_violation, forcing the app's auto-unreserve cleanup
    // (POST /listings/{id}/unreserve) to run first, per TRD §3.
    let err = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(reserver)
        .execute(&pool)
        .await
        .expect_err("deleting a user holding an active reservation must be refused");
    assert_eq!(db_error(&err).code().as_deref(), Some("23503"));

    // App-level cleanup: unreserve returns the listing to 'active' and clears
    // the reservation fields.
    sqlx::query(
        "UPDATE listings SET status = 'active', reserved_by = NULL, reserved_at = NULL WHERE id = $1",
    )
    .bind(listing)
    .execute(&pool)
    .await
    .expect("unreserve listing");

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(reserver)
        .execute(&pool)
        .await
        .expect("delete user after cleanup");

    // The listing survives the account deletion (not cascaded) and its
    // reservation reference is gone.
    let (listing_exists, reserved_by): (bool, Option<Uuid>) = sqlx::query_as(
        "SELECT EXISTS(SELECT 1 FROM listings WHERE id = $1),
                (SELECT reserved_by FROM listings WHERE id = $1)",
    )
    .bind(listing)
    .fetch_one(&pool)
    .await
    .expect("read listing state");
    assert!(listing_exists, "listing must not be cascade-deleted");
    assert_eq!(reserved_by, None, "reserved_by must be NULL after cleanup");
}

#[sqlx::test]
async fn deleting_user_cascades_to_refresh_tokens(pool: PgPool) {
    let school = seed_school(&pool).await;
    let user = seed_user(&pool, school, "user@test.edu", "User").await;
    let token = seed_refresh_token(&pool, user, "sha256-hash-1").await;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(user)
        .execute(&pool)
        .await
        .expect("delete user");

    assert!(
        !uuid_row_exists(&pool, "refresh_tokens", token).await,
        "refresh token must cascade-delete with its user"
    );
}

#[sqlx::test]
async fn deleting_seller_cascades_to_listings_and_images(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;
    let image = seed_image(&pool, listing, 0).await;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(seller)
        .execute(&pool)
        .await
        .expect("delete seller");

    assert!(
        !uuid_row_exists(&pool, "listings", listing).await,
        "listings must cascade-delete with their seller"
    );
    assert!(
        !uuid_row_exists(&pool, "images", image).await,
        "images must cascade-delete with their listing"
    );
}

#[sqlx::test]
async fn deleting_user_cascades_to_chats_and_messages(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let buyer = seed_user(&pool, school, "buyer@test.edu", "Buyer").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;
    let chat = seed_chat(&pool, listing, buyer, seller).await;
    let msg_to_seller = seed_message(&pool, chat, buyer, "is this still available?").await;
    let msg_to_buyer = seed_message(&pool, chat, seller, "yes!").await;

    // Deleting either participant removes the thread (buyer_id/seller_id →
    // users CASCADE), which in turn removes its messages (chat_id → chats
    // CASCADE).
    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(buyer)
        .execute(&pool)
        .await
        .expect("delete buyer");

    assert!(
        !uuid_row_exists(&pool, "chats", chat).await,
        "chats must cascade-delete with a participant"
    );
    assert!(
        !uuid_row_exists(&pool, "messages", msg_to_seller).await
            && !uuid_row_exists(&pool, "messages", msg_to_buyer).await,
        "messages must cascade-delete with their chat"
    );

    // Also prove sender_id → users cascades directly: in a fresh thread where
    // the deleted user is only a message sender (not a chat participant whose
    // own cascade would remove the thread), the message must still disappear.
    let fresh_buyer = seed_user(&pool, school, "buyer2@test.edu", "Buyer Two").await;
    let chat3 = seed_chat(&pool, listing, fresh_buyer, seller).await;
    let seller_message = seed_message(&pool, chat3, seller, "ping").await;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(seller)
        .execute(&pool)
        .await
        .expect("delete seller");

    assert!(
        !uuid_row_exists(&pool, "messages", seller_message).await
            && !uuid_row_exists(&pool, "chats", chat3).await,
        "seller-owned rows must cascade-delete with the seller"
    );
}

#[sqlx::test]
async fn deleting_listing_cascades_to_chats_messages_images_and_reports(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let buyer = seed_user(&pool, school, "buyer@test.edu", "Buyer").await;
    let reporter = seed_user(&pool, school, "reporter@test.edu", "Reporter").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;
    let image = seed_image(&pool, listing, 0).await;
    let chat = seed_chat(&pool, listing, buyer, seller).await;
    let message = seed_message(&pool, chat, buyer, "interested").await;
    let report = seed_report(&pool, reporter, Some(listing), None).await;

    sqlx::query("DELETE FROM listings WHERE id = $1")
        .bind(listing)
        .execute(&pool)
        .await
        .expect("delete listing");

    assert!(
        !uuid_row_exists(&pool, "images", image).await
            && !uuid_row_exists(&pool, "chats", chat).await
            && !uuid_row_exists(&pool, "messages", message).await
            && !uuid_row_exists(&pool, "reports", report).await,
        "listing children (images, chats, messages, reports) must cascade-delete"
    );
}

#[sqlx::test]
async fn deleting_chat_cascades_to_messages(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let buyer = seed_user(&pool, school, "buyer@test.edu", "Buyer").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;
    let chat = seed_chat(&pool, listing, buyer, seller).await;
    let m1 = seed_message(&pool, chat, buyer, "hi").await;
    let m2 = seed_message(&pool, chat, seller, "hello").await;

    sqlx::query("DELETE FROM chats WHERE id = $1")
        .bind(chat)
        .execute(&pool)
        .await
        .expect("delete chat");

    assert!(
        !uuid_row_exists(&pool, "messages", m1).await
            && !uuid_row_exists(&pool, "messages", m2).await,
        "messages must cascade-delete with their chat"
    );
}

#[sqlx::test]
async fn deleting_category_cascades_to_listings(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;

    sqlx::query("DELETE FROM categories WHERE id = $1")
        .bind(category)
        .execute(&pool)
        .await
        .expect("delete category");

    assert!(
        !uuid_row_exists(&pool, "listings", listing).await,
        "listings must cascade-delete with their category"
    );
}

#[sqlx::test]
async fn deleting_user_cascades_to_reports(pool: PgPool) {
    let school = seed_school(&pool).await;
    let reporter = seed_user(&pool, school, "reporter@test.edu", "Reporter").await;
    let reported = seed_user(&pool, school, "reported@test.edu", "Reported").await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let other_reporter = seed_user(&pool, school, "other@test.edu", "Other").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;

    // Report A: reporter → listing (covers reports.reporter_id → users).
    // Report B: other_reporter → reported (covers reports.reported_user_id → users).
    let report_a = seed_report(&pool, reporter, Some(listing), None).await;
    let report_b = seed_report(&pool, other_reporter, None, Some(reported)).await;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(reporter)
        .execute(&pool)
        .await
        .expect("delete reporter");

    assert!(
        !uuid_row_exists(&pool, "reports", report_a).await,
        "reports must cascade-delete with their reporter"
    );
    assert!(
        uuid_row_exists(&pool, "reports", report_b).await,
        "unrelated report must survive"
    );

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(reported)
        .execute(&pool)
        .await
        .expect("delete reported user");

    assert!(
        !uuid_row_exists(&pool, "reports", report_b).await,
        "reports must cascade-delete with their reported user"
    );
}

// ---------------------------------------------------------------------------
// CHECK / UNIQUE constraint behavior (TRD §3)
// ---------------------------------------------------------------------------

#[sqlx::test]
async fn reserved_fields_consistent_rejects_inconsistent_states(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let reserver = seed_user(&pool, school, "reserver@test.edu", "Reserver").await;
    let category = seed_category(&pool).await;

    // Valid: reserved status with both reservation fields set.
    let reserved = seed_reserved_listing(&pool, seller, reserver, category).await;
    assert!(uuid_row_exists(&pool, "listings", reserved).await);

    // Valid: non-reserved status with no reserved_by.
    let active = seed_listing(&pool, seller, category).await;
    assert!(uuid_row_exists(&pool, "listings", active).await);

    // Invalid: status = 'reserved' but reserved_by / reserved_at missing.
    let err = sqlx::query(
        "INSERT INTO listings (seller_id, category_id, title, condition, status)
         VALUES ($1, $2, 'Bad reservation', 'used', 'reserved')",
    )
    .bind(seller)
    .bind(category)
    .execute(&pool)
    .await
    .expect_err("reserved status without reservation fields must be rejected");
    assert_eq!(
        db_error(&err).constraint(),
        Some("reserved_fields_consistent")
    );

    // Invalid: reserved_by set while status is not 'reserved'.
    let err = sqlx::query(
        "INSERT INTO listings (seller_id, category_id, title, condition, status, reserved_by)
         VALUES ($1, $2, 'Bad active', 'used', 'active', $3)",
    )
    .bind(seller)
    .bind(category)
    .bind(reserver)
    .execute(&pool)
    .await
    .expect_err("reserved_by set while not reserved must be rejected");
    assert_eq!(
        db_error(&err).constraint(),
        Some("reserved_fields_consistent")
    );
}

#[sqlx::test]
async fn max_three_images_rejects_duplicate_position(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;

    // Valid: three images at distinct positions 0..=2.
    seed_image(&pool, listing, 0).await;
    seed_image(&pool, listing, 1).await;
    seed_image(&pool, listing, 2).await;

    // Invalid: a fourth image reusing an existing (listing_id, position) pair.
    let err = sqlx::query(
        "INSERT INTO images (listing_id, object_key, position) VALUES ($1, 'dup.jpg', 0)",
    )
    .bind(listing)
    .execute(&pool)
    .await
    .expect_err("duplicate (listing_id, position) must be rejected");
    assert_eq!(db_error(&err).constraint(), Some("max_three_images"));
}

#[sqlx::test]
async fn unique_thread_rejects_duplicate_buyer_per_listing(pool: PgPool) {
    let school = seed_school(&pool).await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let buyer_a = seed_user(&pool, school, "buyer-a@test.edu", "Buyer A").await;
    let buyer_b = seed_user(&pool, school, "buyer-b@test.edu", "Buyer B").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;

    // Valid: first thread for this buyer/listing pair.
    let chat = seed_chat(&pool, listing, buyer_a, seller).await;
    assert!(uuid_row_exists(&pool, "chats", chat).await);

    // Invalid: a second thread for the same buyer on the same listing.
    let err =
        sqlx::query("INSERT INTO chats (listing_id, buyer_id, seller_id) VALUES ($1, $2, $3)")
            .bind(listing)
            .bind(buyer_a)
            .bind(seller)
            .execute(&pool)
            .await
            .expect_err("duplicate (listing_id, buyer_id) thread must be rejected");
    assert_eq!(db_error(&err).constraint(), Some("unique_thread"));

    // Valid: a different buyer can still open a thread on the same listing.
    let chat_b = seed_chat(&pool, listing, buyer_b, seller).await;
    assert!(uuid_row_exists(&pool, "chats", chat_b).await);
}

#[sqlx::test]
async fn report_target_rejects_report_without_target(pool: PgPool) {
    let school = seed_school(&pool).await;
    let reporter = seed_user(&pool, school, "reporter@test.edu", "Reporter").await;
    let reported = seed_user(&pool, school, "reported@test.edu", "Reported").await;
    let seller = seed_user(&pool, school, "seller@test.edu", "Seller").await;
    let category = seed_category(&pool).await;
    let listing = seed_listing(&pool, seller, category).await;

    // Valid: report targeting a listing only.
    let r1 = seed_report(&pool, reporter, Some(listing), None).await;
    assert!(uuid_row_exists(&pool, "reports", r1).await);

    // Valid: report targeting a user only.
    let r2 = seed_report(&pool, reporter, None, Some(reported)).await;
    assert!(uuid_row_exists(&pool, "reports", r2).await);

    // Invalid: neither target present.
    let err = sqlx::query(
        "INSERT INTO reports (reporter_id, listing_id, reported_user_id, reason)
         VALUES ($1, NULL, NULL, 'spam')",
    )
    .bind(reporter)
    .execute(&pool)
    .await
    .expect_err("report with no target must be rejected");
    assert_eq!(db_error(&err).constraint(), Some("report_target"));
}
