use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Wire shape for a chat thread in the "my chats" list.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ChatThreadResponse {
    pub id: Uuid,
    pub listing_id: Uuid,
    pub listing_title: String,
    /// The other participant (from the requester's perspective).
    pub counterpart_id: Uuid,
    pub counterpart_name: String,
    pub counterpart_photo_url: Option<String>,
    pub last_message_preview: Option<String>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub last_message_at: Option<time::OffsetDateTime>,
    pub unread_count: i64,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

/// A single chat message.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct MessageResponse {
    pub id: Uuid,
    pub chat_id: Uuid,
    pub sender_id: Uuid,
    pub body: String,
    #[serde(with = "time::serde::rfc3339::option")]
    pub read_at: Option<time::OffsetDateTime>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, Deserialize, validator::Validate)]
pub struct CreateChatRequest {
    pub listing_id: Uuid,
}

#[derive(Debug, Deserialize, validator::Validate)]
pub struct SendMessageRequest {
    #[validate(length(min = 1, max = 5000))]
    pub body: String,
}
