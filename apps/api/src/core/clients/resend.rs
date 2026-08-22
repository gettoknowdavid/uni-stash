use std::sync::Arc;

use crate::core::{config::Config, error::AppError};

/// Inner state for [`ResendClient`].
#[derive(Debug)]
struct ResendClientInner {
    http: reqwest::Client,
    api_key: String,
    base_url: String,
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
        })))
    }

    /// Sends an OTP email for the given purpose.
    ///
    /// `purpose` determines the subject and body:
    /// - `"email_verify"` — "Verify your UniStash email"
    /// - `"password_reset"` — "Reset your UniStash password"
    ///
    /// The OTP code is included as a 6-digit number the user types into the app.
    pub async fn send_otp_email(
        &self,
        to_email: &str,
        otp_code: &str,
        purpose: &str,
    ) -> Result<(), AppError> {
        let (subject, heading) = match purpose {
            "email_verify" => (
                "Verify your UniStash email",
                "Use the code below to verify your email address:",
            ),
            "password_reset" => (
                "Reset your UniStash password",
                "Use the code below to reset your password:",
            ),
            "admin_password_reset" => (
                "Reset your UniStash admin password",
                "Use the code below to reset your admin password:",
            ),
            _ => ("Your UniStash verification code", "Use the code below:"),
        };

        let html = format!(
            "<p>{heading}</p>\n<p style=\"font-size:32px;font-weight:bold;letter-spacing:8px;text-align:center;margin:24px 0;padding:16px;background:#f5f5f5;border-radius:8px;font-family:monospace;\">{otp_code}</p>\n<p>This code expires in 10 minutes.</p>"
        );
        let text = format!("{heading}\n\n{otp_code}\n\nThis code expires in 10 minutes.");

        let body = serde_json::json!({
            "from": "UniStash <onboarding@resend.dev>",
            "to": [to_email],
            "subject": subject,
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
                AppError::Internal(anyhow::anyhow!("failed to send OTP email: {e}"))
            })?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            tracing::error!(
                status = %status,
                body = %text,
                to = to_email,
                purpose = purpose,
                "Resend returned non-2xx"
            );
            return Err(AppError::Internal(anyhow::anyhow!(
                "OTP email failed: HTTP {status}"
            )));
        }

        tracing::info!(to = to_email, purpose = purpose, "OTP email sent");
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
        }))
    }

    #[actix_rt::test]
    async fn send_otp_email_success() {
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
            .send_otp_email("alice@example.com", "123456", "email_verify")
            .await;

        assert!(result.is_ok());
    }

    #[actix_rt::test]
    async fn send_otp_email_non_2xx_returns_error() {
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
            .send_otp_email("bad@example.com", "123456", "email_verify")
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }

    #[actix_rt::test]
    async fn send_otp_email_includes_code_in_body() {
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
            .send_otp_email("bob@test.com", "847291", "email_verify")
            .await
            .unwrap();

        let requests = mock.received_requests().await.unwrap();
        assert_eq!(requests.len(), 1);

        let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
        let html = body["html"].as_str().unwrap();
        assert!(
            html.contains("847291"),
            "HTML should contain the OTP code, got: {html}"
        );
        let subject = body["subject"].as_str().unwrap();
        assert!(
            subject.contains("Verify"),
            "subject should mention verify for email_verify purpose"
        );
    }

    #[actix_rt::test]
    async fn send_otp_email_password_reset_uses_different_subject() {
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
            .send_otp_email("bob@test.com", "111111", "password_reset")
            .await
            .unwrap();

        let requests = mock.received_requests().await.unwrap();
        let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
        let subject = body["subject"].as_str().unwrap();
        assert!(
            subject.contains("Reset"),
            "subject should mention reset for password_reset purpose"
        );
    }

    #[actix_rt::test]
    async fn send_otp_email_connection_refused() {
        let client = resend_client("http://127.0.0.1:1");
        let result = client
            .send_otp_email("alice@example.com", "123456", "email_verify")
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
