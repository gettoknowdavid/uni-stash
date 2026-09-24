//! Realtime publishing abstraction — provider-agnostic (MVP Phase 2).
//!
//! Chat message delivery needs a realtime transport. The MVP uses Pusher
//! Channels, but the platform only ever talks to the [`RealtimePublisher`]
//! trait, so swapping to Ably, a self-hosted WebSocket hub, or anything
//! else later means implementing one trait — no call-site changes.
//!
//! ```text
//! features/chats (publish message.new on private-chat-{id})
//!        │
//!        ▼
//! RealtimePublisher (trait)  ──  pusher.rs (Pusher Channels, MVP)
//!        │                      ──  <future providers>
//!        ▼
//! AppState.realtime: Arc<dyn RealtimePublisher>
//! ```

use async_trait::async_trait;

/// Build a private Pusher channel name from an arbitrary suffix.
/// `private_channel("chat-abc")` → `"private-chat-abc"`.
///
/// Prefer [`chat_channel`] / [`private_user_channel`] over calling this
/// directly — passing a bare uuid (`private_channel(&id.to_string())`)
/// yields `private-{uuid}`, a channel no client subscribes to.
pub fn private_channel(suffix: &str) -> String {
    format!("private-{suffix}")
}

/// The conversation channel every participant subscribes to for live
/// messages: `private-chat-{uuid}`.
///
/// Must stay in lockstep with the mobile client's
/// `RealtimeClient.channelNameFor` (and with `realtime_auth`, which strips
/// the `private-chat-` prefix). Publishing to anything else is accepted by
/// Pusher — it even counts toward "messages sent" — but silently reaches
/// nobody, which is exactly the failure mode this function exists to
/// prevent.
pub fn chat_channel(chat_id: &uuid::Uuid) -> String {
    private_channel(&format!("chat-{chat_id}"))
}

/// Per-user notification channel: `private-user-{uuid}`.
///
/// `send_message` publishes `message.new` here for the *recipient*, so a
/// device hears about messages in every chat it is not actively viewing
/// (in-app notifications, live thread-list/badge updates) without having
/// to subscribe to each conversation's channel. Only the account owner may
/// sign this channel — enforced in `realtime_auth`.
pub fn private_user_channel(user_id: &uuid::Uuid) -> String {
    format!("private-user-{user_id}")
}

/// What the backend publishes over the realtime transport.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RealtimeEvent {
    /// A new message was persisted in a chat. `sender_id` lets clients
    /// tell their own outgoing messages from someone else's (the sender's
    /// device also hears the event through its thread refresh).
    MessageNew {
        chat_id: uuid::Uuid,
        sender_id: uuid::Uuid,
    },
    /// The other participant read up to `last_read_message_id`.
    MessageRead {
        chat_id: uuid::Uuid,
        last_read_message_id: uuid::Uuid,
    },
}

/// Publishes events to realtime channels. Failures are reported to the
/// caller but must never be treated as fatal by feature code — the
/// REST/database row is the source of truth; clients catch up by refetch.
#[async_trait]
pub trait RealtimePublisher: Send + Sync {
    /// Human-readable provider name, used in logs.
    fn name(&self) -> &'static str;

    /// Publish `event` to `channel`. Returns Err only for logging purposes
    /// upstream — callers must degrade gracefully.
    async fn publish(&self, channel: &str, event: &RealtimeEvent) -> Result<(), anyhow::Error>;

    /// Sign a private-channel subscription auth response for a client.
    ///
    /// Returns the provider-specific auth string (e.g. Pusher's
    /// `{"auth":"{key}:{signature}"}` JSON). Returns `None` if the
    /// provider doesn't support channel auth (e.g. null publisher).
    fn authenticate_channel(&self, _socket_id: &str, _channel_name: &str) -> Option<String> {
        None
    }
}

/// No-op publisher for tests and for deployments without realtime
/// configured. Publishing succeeds silently.
pub struct NullPublisher;

#[async_trait]
impl RealtimePublisher for NullPublisher {
    fn name(&self) -> &'static str {
        "null"
    }

    async fn publish(&self, _channel: &str, _event: &RealtimeEvent) -> Result<(), anyhow::Error> {
        Ok(())
    }

    fn authenticate_channel(&self, _socket_id: &str, _channel_name: &str) -> Option<String> {
        None
    }
}

pub mod pusher;

pub use pusher::PusherPublisher;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_names_are_prefixed_predictably() {
        let chat_id = uuid::Uuid::parse_str("67d3e10c-4a2f-4d5b-9c1e-2f4b5a697c88").unwrap();
        assert_eq!(private_channel("chat-abc"), "private-chat-abc");
        assert_eq!(
            private_user_channel(&chat_id),
            "private-user-67d3e10c-4a2f-4d5b-9c1e-2f4b5a697c88"
        );
    }

    #[test]
    fn chat_channel_matches_the_name_mobile_clients_subscribe_to() {
        // Regression: publishing to `private-{uuid}` (forgetting the
        // `chat-` segment) is accepted and counted by Pusher but reaches
        // nobody — the exact "messages go through, page never updates"
        // bug. The client subscribes to `private-chat-{uuid}`.
        let chat_id = uuid::Uuid::new_v4();
        assert_eq!(chat_channel(&chat_id), format!("private-chat-{chat_id}"));
        assert!(chat_channel(&chat_id).starts_with("private-chat-"));
    }

    #[test]
    fn message_new_serializes_with_type_tag_chat_id_and_sender() {
        let chat_id = uuid::Uuid::new_v4();
        let sender_id = uuid::Uuid::new_v4();
        let json =
            serde_json::to_string(&RealtimeEvent::MessageNew { chat_id, sender_id }).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["type"], "message_new");
        assert_eq!(parsed["chat_id"], chat_id.to_string());
        assert_eq!(parsed["sender_id"], sender_id.to_string());
    }
}

/// Build the active publisher from configuration. `pusher` requires its
/// four config values (validated earlier in `Config`); anything else falls
/// back to the no-op publisher so the server still runs — chat simply
/// degrades to REST-only polling.
pub fn from_config(config: &crate::core::config::Config) -> std::sync::Arc<dyn RealtimePublisher> {
    match config.realtime_provider.as_str() {
        "pusher" => {
            let publisher = PusherPublisher::new(
                config.pusher_app_id.clone(),
                config.pusher_key.clone(),
                config.pusher_secret.clone(),
                config.pusher_cluster.clone(),
            );
            std::sync::Arc::new(publisher)
        }
        other => {
            tracing::warn!(
                provider = %other,
                "unknown realtime_provider — realtime publishing disabled (chat falls back to REST polling)"
            );
            std::sync::Arc::new(NullPublisher)
        }
    }
}
