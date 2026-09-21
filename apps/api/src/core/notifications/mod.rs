//! Push notification abstraction — provider-agnostic (MVP Phase 4).
//!
//! Push notifications deliver alerts when the user is not actively using the
//! app: new chat message, reservation created, listing marked sold. The MVP
//! uses Pusher Beams, but feature code only ever talks to [`PushSender`],
//! so swapping to Firebase / OneSignal / etc. means writing one alternate
//! impl file.
//!
//! ```text
//! features/chats (send notification on message.new)
//! features/listings (send notification on reserve / mark-sold)
//!        │
//!        ▼
//! PushSender (trait)  ──  beams.rs (Pusher Beams, MVP)
//!        │              ──  <future providers>
//!        ▼
//! AppState.push_sender: Arc<dyn PushSender>
//! ```

use async_trait::async_trait;

/// Sends push notifications to individual users. Implementations are
/// fire-and-forget: failures are logged but never surface to the caller —
/// the REST/database row is the source of truth.
#[async_trait]
pub trait PushSender: Send + Sync {
    /// Human-readable provider name, used in logs.
    fn name(&self) -> &'static str;

    /// Send a push notification to every registered device of [user_id].
    /// `data` is an optional slice of key-value pairs the client can use for
    /// deep-linking (e.g. `[("chat_id", "...")]`).
    async fn send_to_user(
        &self,
        user_id: uuid::Uuid,
        title: &str,
        body: &str,
        data: Option<&[(&str, &str)]>,
    ) -> Result<(), anyhow::Error>;
}

/// No-op sender for tests and for deployments without push configured.
/// Sending succeeds silently.
pub struct NullPushSender;

#[async_trait]
impl PushSender for NullPushSender {
    fn name(&self) -> &'static str {
        "null"
    }

    async fn send_to_user(
        &self,
        _user_id: uuid::Uuid,
        _title: &str,
        _body: &str,
        _data: Option<&[(&str, &str)]>,
    ) -> Result<(), anyhow::Error> {
        Ok(())
    }
}

pub mod beams;

pub use beams::BeamsPushSender;

/// Build the active push sender from configuration.
pub fn from_config(config: &crate::core::config::Config) -> std::sync::Arc<dyn PushSender> {
    match config.realtime_provider.as_str() {
        "pusher" => {
            if config.pusher_instance_id.is_empty() || config.pusher_secret_key.is_empty() {
                tracing::warn!(
                    "realtime_provider=pusher but PUSHER_INSTANCE_ID / PUSHER_SECRET_KEY not set \
                     — push notifications disabled"
                );
                return std::sync::Arc::new(NullPushSender);
            }
            let sender = BeamsPushSender::new(
                config.pusher_instance_id.clone(),
                config.pusher_secret_key.clone(),
            );
            std::sync::Arc::new(sender)
        }
        other => {
            tracing::warn!(
                provider = %other,
                "unknown realtime_provider — push notifications disabled"
            );
            std::sync::Arc::new(NullPushSender)
        }
    }
}
