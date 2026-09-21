//! Pusher Beams implementation of [`PushSender`](super::PushSender).
//!
//! Uses the Pusher Beams publish API:
//! `POST https://rest.pusher.com/publish-api/v1/instances/{instanceId}/publishes/interests/{interest}`
//!
//! Device tokens are registered via `/api/v1/notifications/register-device`
//! and stored in the `device_tokens` table. Each device is subscribed to a
//! user-specific interest (`user-{uuid}`), enabling targeted sends.
//!
//! Provider isolation: nothing else in the codebase imports `beams`-specific
//! types — feature code talks to the trait only.

use async_trait::async_trait;

use super::PushSender;

/// Pusher Beams push notification sender.
///
/// Pusher Beams uses "interests" as the addressing mechanism. Each user's
/// devices are subscribed to an interest named `user-{user_id}`. When we
/// want to notify a user, we publish to that interest.
#[derive(Clone)]
pub struct BeamsPushSender {
    http: reqwest::Client,
    instance_id: String,
    secret_key: String,
}

impl BeamsPushSender {
    pub fn new(instance_id: String, secret_key: String) -> Self {
        Self {
            http: reqwest::Client::new(),
            instance_id,
            secret_key,
        }
    }

    /// Build the interest name for a user's devices.
    pub fn user_interest(user_id: &uuid::Uuid) -> String {
        format!("user-{}", user_id)
    }
}

#[async_trait]
impl PushSender for BeamsPushSender {
    fn name(&self) -> &'static str {
        "beams"
    }

    async fn send_to_user(
        &self,
        user_id: uuid::Uuid,
        title: &str,
        body: &str,
        data: Option<&[(&str, &str)]>,
    ) -> Result<(), anyhow::Error> {
        let interest = Self::user_interest(&user_id);

        let mut payload_data = serde_json::Map::new();
        if let Some(pairs) = data {
            for (k, v) in pairs {
                payload_data.insert(k.to_string(), serde_json::Value::String(v.to_string()));
            }
        }

        let body_obj = serde_json::json!({
            "interests": [interest],
            "apns": {
                "aps": {
                    "alert": {
                        "title": title,
                        "body": body,
                    },
                    "sound": "default",
                },
            },
            "fcm": {
                "notification": {
                    "title": title,
                    "body": body,
                },
                "data": payload_data,
            },
            "web": {
                "notification": {
                    "title": title,
                    "body": body,
                },
            },
        });

        let url = format!(
            "https://rest.pusher.com/publish-api/v1/instances/{}/publishes/interests/{}",
            self.instance_id, interest,
        );

        let resp = self
            .http
            .post(&url)
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", self.secret_key))
            .json(&body_obj)
            .send()
            .await?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("beams publish failed: status {status}, body: {text}");
        }
        Ok(())
    }
}
