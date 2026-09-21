use uuid::Uuid;

use crate::core::error::AppError;
use crate::features::chats::models::{ChatThreadResponse, MessageResponse};

#[derive(Clone, Debug)]
pub struct ChatsRepo {
    db: sqlx::PgPool,
}

impl ChatsRepo {
    pub fn new(db: sqlx::PgPool) -> Self {
        Self { db }
    }

    /// Create (or fetch the existing) thread for a (listing, buyer) pair.
    /// The DB unique constraint `unique_thread` makes this idempotent; the
    /// ON CONFLICT RETURNING handles the race where two requests create the
    /// same thread concurrently.
    pub async fn create_for_listing(
        &self,
        listing_id: Uuid,
        buyer_id: Uuid,
    ) -> Result<Uuid, AppError> {
        let row = sqlx::query!(
            "INSERT INTO chats (listing_id, buyer_id, seller_id)
             SELECT $1, $2, l.seller_id FROM listings l WHERE l.id = $1
             ON CONFLICT (listing_id, buyer_id) DO UPDATE SET listing_id = EXCLUDED.listing_id
             RETURNING id",
            listing_id,
            buyer_id,
        )
        .fetch_optional(&self.db)
        .await?
        .ok_or_else(|| AppError::NotFound("listing not found".into()))?;
        Ok(row.id)
    }

    /// Fetch a chat with participant info; used for access checks.
    /// Returns (chat_id, buyer_id, seller_id).
    pub async fn participants(&self, chat_id: Uuid) -> Result<Option<(Uuid, Uuid)>, AppError> {
        let row = sqlx::query!(
            "SELECT buyer_id, seller_id FROM chats WHERE id = $1",
            chat_id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(row.map(|r| (r.buyer_id, r.seller_id)))
    }

    /// List the user's threads with listing title, counterpart info, last
    /// message preview, and unread count (messages sent by the counterpart
    /// with read_at IS NULL).
    pub async fn threads_for_user(
        &self,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<ChatThreadResponse>, AppError> {
        let rows = sqlx::query_as!(
            ChatThreadResponse,
            r#"SELECT c.id,
                      c.listing_id,
                      l.title AS listing_title,
                      u.id AS counterpart_id,
                      u.display_name AS counterpart_name,
                      u.photo_url AS counterpart_photo_url,
                      (SELECT m.body FROM messages m WHERE m.chat_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview,
                      c.last_message_at,
                      (SELECT COUNT(*)::BIGINT FROM messages m WHERE m.chat_id = c.id AND m.sender_id <> $1 AND m.read_at IS NULL) AS "unread_count!",
                      c.created_at
               FROM chats c
               JOIN listings l ON l.id = c.listing_id
               JOIN users u ON u.id = CASE WHEN c.buyer_id = $1 THEN c.seller_id ELSE c.buyer_id END
               WHERE c.buyer_id = $1 OR c.seller_id = $1
               ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
               LIMIT $2"#,
            user_id,
            limit,
        )
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Message history for a chat, newest first, cursor-paginated on
    /// (created_at, id) — same convention as listings browse.
    pub async fn messages(
        &self,
        chat_id: Uuid,
        before_created_at: Option<time::OffsetDateTime>,
        before_id: Option<Uuid>,
        limit: i64,
    ) -> Result<Vec<MessageResponse>, AppError> {
        let rows = sqlx::query_as!(
            MessageResponse,
            r#"SELECT id, chat_id, sender_id, body, read_at, created_at
               FROM messages
               WHERE chat_id = $1
                 AND ($2::timestamptz IS NULL OR (created_at, id) < ($2, $3::uuid))
               ORDER BY created_at DESC, id DESC
               LIMIT $4"#,
            chat_id,
            before_created_at,
            before_id,
            limit,
        )
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    /// Insert a message and bump the thread's last_message_at atomically.
    pub async fn send_message(
        &self,
        chat_id: Uuid,
        sender_id: Uuid,
        body: &str,
    ) -> Result<MessageResponse, AppError> {
        let mut tx = self.db.begin().await?;

        let msg = sqlx::query_as!(
            MessageResponse,
            r#"INSERT INTO messages (chat_id, sender_id, body)
               VALUES ($1, $2, $3)
               RETURNING id, chat_id, sender_id, body, read_at, created_at"#,
            chat_id,
            sender_id,
            body,
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query!(
            "UPDATE chats SET last_message_at = now() WHERE id = $1",
            chat_id,
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(msg)
    }

    /// Mark the requester's counterpart messages as read up to now.
    /// Returns the id of the newest message now considered read (for the
    /// realtime `message.read` event), or None if nothing changed.
    pub async fn mark_read(
        &self,
        chat_id: Uuid,
        reader_id: Uuid,
    ) -> Result<Option<Uuid>, AppError> {
        let row = sqlx::query!(
            "UPDATE messages SET read_at = now()
             WHERE chat_id = $1 AND sender_id <> $2 AND read_at IS NULL
             RETURNING id",
            chat_id,
            reader_id,
        )
        .fetch_all(&self.db)
        .await?;
        // rows are unordered; the newest read message is what we broadcast.
        Ok(row.last().map(|r| r.id))
    }

    /// Fetch a single message (used to validate cursor decoding edge cases
    /// and for tests).
    pub async fn message_by_id(
        &self,
        message_id: Uuid,
    ) -> Result<Option<MessageResponse>, AppError> {
        let row = sqlx::query_as!(
            MessageResponse,
            "SELECT id, chat_id, sender_id, body, read_at, created_at FROM messages WHERE id = $1",
            message_id,
        )
        .fetch_optional(&self.db)
        .await?;
        Ok(row)
    }
}
