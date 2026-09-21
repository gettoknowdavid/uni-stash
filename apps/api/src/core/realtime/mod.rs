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
/// Used by both chat (suffix = chat UUID) and notification features.
pub fn private_channel(suffix: &str) -> String {
    format!("private-{suffix}")
}

/// What the backend publishes over the realtime transport.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RealtimeEvent {
    /// A new message was persisted in a chat.
    MessageNew { chat_id: uuid::Uuid },
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
