use std::env::{VarError, var};

use anyhow::Context;

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub jwt_private_key: String,
    pub jwt_public_key: String,
    pub resend_api_key: String,
    pub resend_base_url: String,
    pub allowed_email_domains: Vec<String>,
    pub port: u16,
    pub env: String,
    pub r2_bucket: String,
    pub r2_access_key_id: String,
    pub r2_secret_access_key: String,
    pub r2_endpoint: String,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Config> {
        dotenvy::dotenv().ok();
        Self::from_getter(|key| var(key))
    }

    /// Builds `Config` from an arbitrary var getter so tests can feed a
    /// controlled set of variables instead of mutating the process env.
    fn from_getter<F>(get: F) -> anyhow::Result<Config>
    where
        F: for<'a> Fn(&'a str) -> Result<String, VarError>,
    {
        let allowed_email_domains = required(&get, "ALLOWED_EMAIL_DOMAINS")?
            .split(',')
            .map(str::trim)
            .filter(|domain| !domain.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>();

        if allowed_email_domains.is_empty() {
            anyhow::bail!("ALLOWED_EMAIL_DOMAINS must contain at least one domain");
        }

        Ok(Self {
            database_url: required(&get, "DATABASE_URL")?,
            jwt_private_key: required(&get, "JWT_PRIVATE_KEY")?,
            jwt_public_key: required(&get, "JWT_PUBLIC_KEY")?,
            resend_api_key: required(&get, "RESEND_API_KEY")?,
            resend_base_url: required(&get, "RESEND_BASE_URL")?,
            allowed_email_domains,
            port: match get("PORT") {
                Ok(v) => v.parse::<u16>().context("PORT must be a valid number")?,
                Err(_) => 8080,
            },
            env: required(&get, "ENV")?,
            r2_bucket: required(&get, "R2_BUCKET")?,
            r2_access_key_id: required(&get, "R2_ACCESS_KEY_ID")?,
            r2_secret_access_key: required(&get, "R2_SECRET_ACCESS_KEY")?,
            r2_endpoint: required(&get, "R2_ENDPOINT")?,
        })
    }
}

/// Reads a required var, failing fast with the var's name if it's missing or
/// blank — the "malformed required var" path from CM-1.2.
fn required<F>(get: &F, name: &str) -> anyhow::Result<String>
where
    F: for<'a> Fn(&'a str) -> Result<String, VarError>,
{
    let value = get(name).context(format!("{name} is not set"))?;
    if value.trim().is_empty() {
        anyhow::bail!("{name} must not be empty");
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    /// All required vars set to valid values; individual tests override one.
    fn full_vars() -> Vec<(&'static str, &'static str)> {
        vec![
            ("DATABASE_URL", "postgres://localhost:5432/uni_stash"),
            ("JWT_PRIVATE_KEY", "test-private-key"),
            ("JWT_PUBLIC_KEY", "test-public-key"),
            ("RESEND_API_KEY", "re_test_123"),
            ("RESEND_BASE_URL", "https://api.resend.com"),
            ("ALLOWED_EMAIL_DOMAINS", "uniport.edu.ng"),
            ("PORT", "8080"),
            ("ENV", "dev"),
            ("R2_BUCKET", "uni-stash-images"),
            ("R2_ACCESS_KEY_ID", "test-access-key"),
            ("R2_SECRET_ACCESS_KEY", "test-secret-key"),
            ("R2_ENDPOINT", "https://r2.example.com"),
        ]
    }

    /// Resolves only the provided vars; everything else is "not present".
    fn getter<'a>(
        pairs: &'a [(&'a str, &'a str)],
    ) -> impl Fn(&str) -> Result<String, VarError> + 'a {
        let map: HashMap<&str, &str> = pairs.iter().copied().collect();
        move |key| match map.get(key) {
            Some(value) => Ok((*value).to_string()),
            None => Err(VarError::NotPresent),
        }
    }

    fn without(
        vars: &[(&'static str, &'static str)],
        key: &str,
    ) -> Vec<(&'static str, &'static str)> {
        vars.iter().copied().filter(|(k, _)| *k != key).collect()
    }

    fn with(
        vars: &[(&'static str, &'static str)],
        key: &str,
        value: &'static str,
    ) -> Vec<(&'static str, &'static str)> {
        vars.iter()
            .copied()
            .map(|(k, v)| if k == key { (k, value) } else { (k, v) })
            .collect()
    }

    #[test]
    fn missing_required_var_returns_descriptive_error() {
        let vars = without(&full_vars(), "RESEND_API_KEY");
        let err = Config::from_getter(getter(&vars)).unwrap_err();

        assert!(
            err.to_string().contains("RESEND_API_KEY"),
            "error should name the missing var, got: {err:#}"
        );
    }

    #[test]
    fn blank_required_var_is_rejected() {
        let vars = with(&full_vars(), "DATABASE_URL", "   ");
        let err = Config::from_getter(getter(&vars)).unwrap_err();

        assert!(
            err.to_string().contains("DATABASE_URL"),
            "error should name the malformed var, got: {err:#}"
        );
    }

    #[test]
    fn parses_allowed_email_domains_into_list() {
        let vars = with(
            &full_vars(),
            "ALLOWED_EMAIL_DOMAINS",
            "uniport.edu.ng, student.uni.edu , ",
        );

        let config = Config::from_getter(getter(&vars)).unwrap();
        assert_eq!(
            config.allowed_email_domains,
            vec!["uniport.edu.ng", "student.uni.edu"]
        );
    }

    #[test]
    fn empty_domain_list_is_rejected() {
        let vars = with(&full_vars(), "ALLOWED_EMAIL_DOMAINS", "");
        let err = Config::from_getter(getter(&vars)).unwrap_err();

        assert!(
            err.to_string().contains("ALLOWED_EMAIL_DOMAINS"),
            "error should name the malformed var, got: {err:#}"
        );
    }

    #[test]
    fn malformed_port_returns_descriptive_error() {
        let vars = with(&full_vars(), "PORT", "not-a-number");
        let err = Config::from_getter(getter(&vars)).unwrap_err();

        assert!(
            err.to_string().contains("PORT"),
            "error should name the malformed var, got: {err:#}"
        );
    }

    #[test]
    fn port_defaults_to_8080_when_unset() {
        let vars = without(&full_vars(), "PORT");
        let config = Config::from_getter(getter(&vars)).unwrap();
        assert_eq!(config.port, 8080);
    }
}
