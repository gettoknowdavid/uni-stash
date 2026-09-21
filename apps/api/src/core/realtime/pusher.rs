//! Pusher Channels implementation of [`RealtimePublisher`](super::RealtimePublisher).
//!
//! Uses Pusher's HTTP Trigger Events API:
//! `POST https://api-{cluster}.pusher.com/apps/{app_id}/events`
//! with the standard Pusher REST auth scheme: MD5 of the body, plus an
//! HMAC-SHA256 signature over `POST\n{path}\n{sorted query params}`.
//! Only one endpoint is needed for publishing; channel subscription
//! auth (signing the client's `channel_name` + `socket_id`) lives in
//! [`PusherPublisher::authenticate_channel`] and is exposed to the mobile
//! client via `POST /api/v1/realtime/auth`.
//!
//! Provider isolation: nothing else in the codebase may import
//! `pusher`-specific types — feature code talks to the trait only.

use async_trait::async_trait;
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

use super::{RealtimeEvent, RealtimePublisher};

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone, Debug)]
pub struct PusherPublisher {
    http: reqwest::Client,
    app_id: String,
    key: String,
    secret: String,
    cluster: String,
}

impl PusherPublisher {
    pub fn new(app_id: String, key: String, secret: String, cluster: String) -> Self {
        Self {
            http: reqwest::Client::new(),
            app_id,
            key,
            secret,
            cluster,
        }
    }

    /// Sign a private-channel subscription auth response for a client.
    ///
    /// Returns the JSON string `{ "auth": "{key}:{signature}" }` that the
    /// client SDK expects from the auth endpoint.
    pub fn authenticate_channel(&self, socket_id: &str, channel_name: &str) -> String {
        let payload = format!("{socket_id}:{channel_name}");
        let signature = self.sign(&payload);
        serde_json::json!({ "auth": format!("{}:{}", self.key, signature) }).to_string()
    }

    fn sign(&self, payload: &str) -> String {
        let mut mac = HmacSha256::new_from_slice(self.secret.as_bytes())
            .expect("HMAC accepts any key length");
        mac.update(payload.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }
}

#[derive(serde::Serialize)]
struct TriggerEventBody<'a> {
    name: &'a str,
    channel: &'a str,
    data: String,
}

#[async_trait]
impl RealtimePublisher for PusherPublisher {
    fn name(&self) -> &'static str {
        "pusher"
    }

    async fn publish(&self, channel: &str, event: &RealtimeEvent) -> Result<(), anyhow::Error> {
        let event_name = match event {
            RealtimeEvent::MessageNew { .. } => "message.new",
            RealtimeEvent::MessageRead { .. } => "message.read",
        };
        let data = serde_json::to_string(event)?;

        // Pusher expects MD5 of the raw `data` string in body_md5.
        let md5 = {
            use md5::{Digest as _, Md5};
            let mut hasher = Md5::new();
            hasher.update(data.as_bytes());
            hex::encode(hasher.finalize())
        };

        // Auth signature covers `POST\n{path}\n{sorted query params}`,
        // per Pusher's REST API spec.
        let timestamp = time::OffsetDateTime::now_utc().unix_timestamp();
        let path = format!("/apps/{}/events", self.app_id);
        let query = format!(
            "auth_key={}&auth_timestamp={}&auth_version=1.0&body_md5={}",
            self.key, timestamp, md5
        );
        let signature = self.sign(&format!("POST\n{path}\n{query}"));

        let url = format!(
            "https://api-{cluster}.pusher.com{path}?{query}&auth_signature={signature}",
            cluster = self.cluster,
        );

        let body = TriggerEventBody {
            name: event_name,
            channel,
            data,
        };
        let resp = self.http.post(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("pusher publish failed: status {status}, body: {text}");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_auth_signature_is_deterministic_and_wellformed() {
        let publisher = PusherPublisher::new(
            "1".into(),
            "test-key".into(),
            "test-secret".into(),
            "eu".into(),
        );
        let a = publisher.authenticate_channel("100.1", "private-chat-abc");
        let b = publisher.authenticate_channel("100.1", "private-chat-abc");
        assert_eq!(a, b, "same inputs must give same signature");
        assert!(a.contains("test-key:"), "auth must be prefixed with key");
        assert!(a.starts_with('{') && a.ends_with('}'));
    }

    #[test]
    fn different_sockets_give_different_signatures() {
        let publisher = PusherPublisher::new(
            "1".into(),
            "test-key".into(),
            "test-secret".into(),
            "eu".into(),
        );
        let a = publisher.authenticate_channel("100.1", "private-chat-abc");
        let b = publisher.authenticate_channel("200.2", "private-chat-abc");
        assert_ne!(a, b);
    }
}
