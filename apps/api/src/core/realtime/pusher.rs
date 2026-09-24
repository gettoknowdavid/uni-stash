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

    fn sign(&self, payload: &str) -> String {
        let mut mac = HmacSha256::new_from_slice(self.secret.as_bytes())
            .expect("HMAC accepts any key length");
        mac.update(payload.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    /// Serializes the trigger body and returns `(body, body_md5)`.
    ///
    /// `body_md5` must be the MD5 of the **whole** request body
    /// (`{"name":…,"channel":…,"data":…}`), not of the inner `data`
    /// field — hashing only `data` makes Pusher answer
    /// `400 Invalid body_md5` and silently drop every event (the server
    /// only logs a warning, so clients just never see anything).
    fn body_and_md5(
        event_name: &str,
        channel: &str,
        data: &str,
    ) -> Result<(String, String), anyhow::Error> {
        let body = TriggerEventBody {
            name: event_name,
            channel,
            data: data.to_string(),
        };
        let body = serde_json::to_string(&body)?;
        let md5 = {
            use md5::{Digest as _, Md5};
            let mut hasher = Md5::new();
            hasher.update(body.as_bytes());
            hex::encode(hasher.finalize())
        };
        Ok((body, md5))
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

        // The exact bytes we send; `body_md5` covers them (see body_and_md5).
        let (body, md5) = Self::body_and_md5(event_name, channel, &data)?;

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

        let resp = self
            .http
            .post(&url)
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("pusher publish failed: status {status}, body: {text}");
        }
        Ok(())
    }

    fn authenticate_channel(&self, socket_id: &str, channel_name: &str) -> Option<String> {
        let payload = format!("{socket_id}:{channel_name}");
        let signature = self.sign(&payload);
        Some(serde_json::json!({ "auth": format!("{}:{}", self.key, signature) }).to_string())
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
        use RealtimePublisher as _;
        let a = publisher
            .authenticate_channel("100.1", "private-chat-abc")
            .unwrap();
        let b = publisher
            .authenticate_channel("100.1", "private-chat-abc")
            .unwrap();
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
        use RealtimePublisher as _;
        let a = publisher
            .authenticate_channel("100.1", "private-chat-abc")
            .unwrap();
        let b = publisher
            .authenticate_channel("200.2", "private-chat-abc")
            .unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn body_md5_hashes_the_whole_body_not_just_data() {
        let data = r#"{"type":"message_new","chat_id":"abc"}"#;
        let (body, md5) =
            PusherPublisher::body_and_md5("message.new", "private-chat-abc", data).unwrap();

        // Pusher's spec: body_md5 = MD5 of the entire request body.
        let expected = {
            use md5::{Digest as _, Md5};
            let mut hasher = Md5::new();
            hasher.update(body.as_bytes());
            hex::encode(hasher.finalize())
        };
        assert_eq!(md5, expected, "body_md5 must cover the whole body");

        // The historical bug: hashing only the inner `data` payload —
        // Pusher answers `400 Invalid body_md5` and drops every event.
        let data_only = {
            use md5::{Digest as _, Md5};
            let mut hasher = Md5::new();
            hasher.update(data.as_bytes());
            hex::encode(hasher.finalize())
        };
        assert_ne!(md5, data_only);

        // Field presence as Pusher expects them.
        let parsed: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(parsed["name"], "message.new");
        assert_eq!(parsed["channel"], "private-chat-abc");
        assert_eq!(parsed["data"], data);
    }
}
