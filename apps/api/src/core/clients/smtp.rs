use std::sync::Arc;

use lettre::message::header::ContentType;
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};

use crate::core::{config::Config, error::AppError};

#[derive(Debug)]
struct SmtpClientInner {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from_address: String,
}

/// Sends transactional email via SMTP (Brevo, or any SMTP provider).
#[derive(Clone, Debug)]
pub struct SmtpClient(Arc<SmtpClientInner>);

impl SmtpClient {
    pub fn new(config: &Config) -> anyhow::Result<Self, AppError> {
        let credentials = Credentials::new(config.smtp_user.clone(), config.smtp_password.clone());

        let transport = AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&config.smtp_host)
            .map_err(|e| {
                AppError::Internal(anyhow::anyhow!("failed to build SMTP transport: {e}"))
            })?
            .port(config.smtp_port)
            .credentials(credentials)
            .build();

        Ok(Self(Arc::new(SmtpClientInner {
            transport,
            from_address: config.smtp_from.clone(),
        })))
    }

    /// Sends an OTP email for the given purpose.
    ///
    /// `purpose` determines the subject and body:
    /// - `"email_verify"` — "Verify your UniStash email"
    /// - `"password_reset"` — "Reset your UniStash password"
    /// - `"admin_password_reset"` — "Reset your UniStash admin password"
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
        let email =
            Message::builder()
                .from(self.0.from_address.parse().map_err(|e| {
                    AppError::Internal(anyhow::anyhow!("invalid from address: {e}"))
                })?)
                .to(to_email
                    .parse()
                    .map_err(|e| AppError::Internal(anyhow::anyhow!("invalid to address: {e}")))?)
                .subject(subject)
                .header(ContentType::TEXT_HTML)
                .body(html)
                .map_err(|e| AppError::Internal(anyhow::anyhow!("failed to build email: {e}")))?;

        self.0.transport.send(email).await.map_err(|e| {
            tracing::error!(error = %e, to = to_email, "SMTP send failed");
            AppError::Internal(anyhow::anyhow!("failed to send OTP email: {e}"))
        })?;

        tracing::info!(to = to_email, purpose = purpose, "OTP email sent");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> Config {
        Config {
            database_url: "postgres://localhost:5432/uni_stash".into(),
            jwt_private_key: "test".into(),
            jwt_public_key: "test".into(),
            smtp_host: "smtp.example.com".into(),
            smtp_port: 587,
            smtp_user: "test@example.com".into(),
            smtp_password: "test_password".into(),
            smtp_from: "Test <test@example.com>".into(),
            frontend_base_url: "https://example.com".into(),
            port: 8080,
            env: "test".into(),
            r2_bucket: "".into(),
            r2_access_key_id: "".into(),
            r2_secret_access_key: "".into(),
            r2_endpoint: "".into(),
        }
    }

    #[actix_rt::test]
    async fn send_otp_email_connection_refused() {
        let config = test_config();
        let client = SmtpClient::new(&config).unwrap();
        let result = client
            .send_otp_email("alice@example.com", "123456", "email_verify")
            .await;

        let err = result.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
