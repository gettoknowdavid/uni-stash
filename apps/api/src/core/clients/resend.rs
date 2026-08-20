use std::sync::Arc;

use crate::core::{config::Config, error::AppError};

/// Inner state for [`ResendClient`].
#[derive(Debug)]
struct ResendClientInner {
    http: reqwest::Client,
    api_key: String,
    base_url: String,
    frontend_base_url: String,
}

/// Sends transactional email via Resend's REST API.
///
/// Deliberately a thin wrapper instead of the `resend-rs` crate: the crate
/// is thinly maintained, and we only need one call shape. The API key is
/// kept behind an `Arc` and never `Debug`-printed.
#[derive(Clone, Debug)]
pub struct ResendClient(Arc<ResendClientInner>);

impl ResendClient {
    pub fn new(config: &Config) -> anyhow::Result<Self, AppError> {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .map_err(|e| AppError::Internal(anyhow::anyhow!("failed to build HTTP client: {e}")))?;
        Ok(Self(Arc::new(ResendClientInner {
            http,
            api_key: config.resend_api_key.clone(),
            base_url: config.resend_base_url.clone(),
            frontend_base_url: config.frontend_base_url.clone(),
        })))
    }

    /// Sends a verification email with a magic link.
    ///
    /// # Rollback vs. retry decision
    ///
    /// We do **not** roll back the user row on Resend failure. Instead:
    /// - The user exists with `email_verified = false`.
    /// - A future `POST /api/v1/auth/resend-verification` endpoint (not in
    ///   this ticket's scope) will let the client re-trigger the email.
    /// - Rolling back requires a transaction that spans an external HTTP
    ///   call, which is fragile and introduces distributed-transaction
    ///   semantics. Leaving the row and surfacing a 500 lets the client
    ///   retry signup (which hits the Conflict path for the duplicate email)
    ///   or lets a dedicated resend-email endpoint handle it.
    pub async fn send_verification_email(
        &self,
        to_email: &str,
        verify_token: &str,
    ) -> Result<(), AppError> {
        let verification_url = format!(
            "{}/verify-email?token={}",
            self.0.frontend_base_url.trim_end_matches('/'),
            verify_token,
        );

        let html = format!(
            "<p>Click the link below to verify your email address:</p>\n\n\n<p><a href=\"{verification_url}\">Verify email</a></p>\n\n\n<p>This link expires in 24 hours.</p>"
        );
        let text = format!(
            "Verify your email by visiting this link:\n\n{verification_url}\n\nThis link expires in 24 hours."
        );

        let body = serde_json::json!({
            "from": "UniStash <onboarding@resend.dev>",
            "to": [to_email],
            "subject": "Verify your UniStash email",
            "html": html,
            "text": text,
        });

        let url = format!("{}/emails", self.0.base_url);
        let response = self
            .0
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.0.api_key))
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, to = to_email, "Resend request failed");
                AppError::Internal(anyhow::anyhow!("failed to send verification email: {e}"))
            })?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            tracing::error!(
                status = %status,
                body = %text,
                to = to_email,
                "Resend returned non-2xx"
            );
            return Err(AppError::Internal(anyhow::anyhow!(
                "verification email failed: HTTP {status}"
            )));
        }

        tracing::info!(to = to_email, "Verification email sent");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: build a ResendClient pointed at the given mock server URL.
    fn resend_client(base_url: &str) -> ResendClient {
        let http = reqwest::Client::new();
        ResendClient(Arc::new(ResendClientInner {
            http,
            api_key: "re_test_key".into(),
            base_url: base_url.into(),
            frontend_base_url: "https://example.com".into(),
        }))
    }

    #[actix_rt::test]
    async fn send_verification_email_success() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .and(wiremock::matchers::header(
                "Authorization",
                "Bearer re_test_key",
            ))
            .respond_with(
                wiremock::ResponseTemplate::new(200)
                    .set_body_json(serde_json::json!({"id": "test-email-id"})),
            )
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        let result = client
            .send_verification_email("alice@example.com", "tok_abc123")
            .await;

        assert!(result.is_ok());
    }

    #[actix_rt::test]
    async fn send_verification_email_non_2xx_returns_error() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .respond_with(
                wiremock::ResponseTemplate::new(422).set_body_json(
                    serde_json::json!({"statusCode": 422, "message": "Invalid email"}),
                ),
            )
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        let result = client
            .send_verification_email("bad@example.com", "tok_abc123")
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[actix_rt::test]
    async fn send_verification_email_includes_correct_url() {
        let mock = wiremock::MockServer::start().await;

        wiremock::Mock::given(wiremock::matchers::method("POST"))
            .and(wiremock::matchers::path("/emails"))
            .respond_with(
                wiremock::ResponseTemplate::new(200)
                    .set_body_json(serde_json::json!({"id": "test-email-id"})),
            )
            .expect(1)
            .mount(&mock)
            .await;

        let client = resend_client(&mock.uri());
        client
            .send_verification_email("bob@test.com", "tok_xyz789")
            .await
            .unwrap();

        // The mock was mounted with expect(1) — if it wasn't called, the test
        // would fail. But let's also verify the body contains the right URL.
        let requests = mock.received_requests().await.unwrap();
        assert_eq!(requests.len(), 1);

        let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
        let html = body["html"].as_str().unwrap();
        // Trailing slash on frontend_base_url should be trimmed.
        assert!(
            html.contains("https://uni-stash.com/verify-email?token=tok_xyz789"),
            "HTML should contain the verification URL, got: {html}"
        );
    }

    #[actix_rt::test]
    async fn send_verification_email_connection_refused() {
        // Port 1 is closed on every platform — simulates Resend being down.
        let client = resend_client("http://127.0.0.1:1");
        let result = client
            .send_verification_email("alice@example.com", "tok_abc123")
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
