//! Pusher Beams implementation of [`PushSender`](super::PushSender).
//!
//! Uses the Pusher Beams publish API:
//! `POST https://rest.pusher.com/publish-api/v1/instances/{instanceId}/publishes/interests/{interest}`
//!
//! Each user's devices are subscribed to a interest (`user-{uuid}`) by the
//! mobile app (`PushNotifications.onUserSignedIn`), enabling targeted sends.
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
        format!("user-{user_id}")
    }
}

/// Build the Beams publish request body.
///
/// Custom data must live under the `data` key of each provider section —
/// Beams drops anything outside it. On top of the flat pairs (the fast path
/// for foreground delivery), the payload is also nested under `info`, the
/// convention the Beams SDKs document for retrieving data from a
/// notification tap: iOS `getInitialMessage()` reads `data.info`, and
/// Android's FCM data map may carry the nested object JSON-stringified.
/// The mobile parser (`parseChatPush`) understands both shapes.
fn build_publish_body(
    interest: &str,
    title: &str,
    body: &str,
    data: Option<&[(&str, &str)]>,
) -> serde_json::Value {
    let mut payload_data = serde_json::Map::new();
    if let Some(pairs) = data {
        for (k, v) in pairs {
            payload_data.insert(k.to_string(), serde_json::Value::String(v.to_string()));
        }
    }

    let mut data_with_info = payload_data.clone();
    data_with_info.insert(
        "info".to_string(),
        serde_json::Value::Object(payload_data.clone()),
    );

    serde_json::json!({
        "interests": [interest],
        "apns": {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body,
                },
                "sound": "default",
            },
            "data": data_with_info,
        },
        "fcm": {
            "notification": {
                "title": title,
                "body": body,
            },
            "data": data_with_info,
        },
        "web": {
            "notification": {
                "title": title,
                "body": body,
            },
            "data": payload_data,
        },
    })
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
        let body_obj = build_publish_body(&interest, title, body, data);

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn user_interest_is_prefixed_with_user() {
        let id = uuid::Uuid::parse_str("67d3e10c-4a2f-4d5b-9c1e-2f4b5a697c88").unwrap();
        assert_eq!(BeamsPushSender::user_interest(&id), "user-67d3e10c-4a2f-4d5b-9c1e-2f4b5a697c88");
    }

    #[test]
    fn publish_body_addresses_the_interest_and_carries_title_body() {
        let body = build_publish_body("user-u1", "New message", "Hey!", None);

        assert_eq!(body["interests"], serde_json::json!(["user-u1"]));
        assert_eq!(body["apns"]["aps"]["alert"]["title"], "New message");
        assert_eq!(body["apns"]["aps"]["alert"]["body"], "Hey!");
        assert_eq!(body["apns"]["aps"]["sound"], "default");
        assert_eq!(body["fcm"]["notification"]["title"], "New message");
        assert_eq!(body["web"]["notification"]["body"], "Hey!");
    }

    #[test]
    fn custom_data_is_reachable_on_every_platform() {
        let data = [("chat_id", "c1"), ("sender_name", "Ada")];
        let body = build_publish_body("user-u1", "T", "B", Some(&data));

        // FCM: flat pairs for the foreground path, `info` for the SDK
        // convention / cold-start path.
        let fcm_data = body["fcm"]["data"].as_object().expect("fcm data");
        assert_eq!(fcm_data["chat_id"], "c1");
        assert_eq!(fcm_data["info"]["chat_id"], "c1");
        assert_eq!(fcm_data["info"]["sender_name"], "Ada");

        // APNs: same two shapes under `apns.data` — without this key iOS
        // receives no custom data at all.
        let apns_data = body["apns"]["data"].as_object().expect("apns data");
        assert_eq!(apns_data["chat_id"], "c1");
        assert_eq!(apns_data["info"]["chat_id"], "c1");

        // Web: flat string payload.
        assert_eq!(body["web"]["data"]["chat_id"], "c1");
        assert!(body["web"]["data"]["info"].is_null());
    }

    #[test]
    fn publish_body_without_data_still_has_an_info_object() {
        let body = build_publish_body("user-u1", "T", "B", None);

        let fcm_data = body["fcm"]["data"].as_object().expect("fcm data");
        assert_eq!(fcm_data.len(), 1, "only the info key expected");
        assert!(fcm_data["info"].is_object());
        assert!(fcm_data["info"].as_object().unwrap().is_empty());

        assert!(body["apns"]["data"].is_object());
        assert!(body["web"]["data"].is_object());
    }

    #[test]
    fn data_keys_never_escape_the_provider_sections() {
        // Beams drops custom data outside `data` — assert the flat pairs
        // don't leak to the top level or into `aps`/`notification`.
        let data = [("chat_id", "c1")];
        let body = build_publish_body("user-u1", "T", "B", Some(&data));

        assert!(body.get("chat_id").is_none());
        assert!(body["apns"]["aps"].get("chat_id").is_none());
        assert!(body["fcm"]["notification"].get("chat_id").is_none());
    }
}
