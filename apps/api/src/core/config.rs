use std::env::{VarError, var};
use std::fs;

use anyhow::Context;

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub jwt_private_key: String,
    pub jwt_public_key: String,
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_user: String,
    pub smtp_password: String,
    pub smtp_from: String,
    pub frontend_base_url: String,
    pub port: u16,
    pub env: String,
    pub r2_bucket: String,
    pub r2_access_key_id: String,
    pub r2_secret_access_key: String,
    pub r2_endpoint: String,
}

impl Config {
    /// Load configuration from environment variables.
    ///
    /// Environment-specific dotenv loading:
    /// - If `ENV` is already set in the process env, loads `.env.{ENV}`
    ///   (e.g. `.env.prod`, `.env.staging`). Falls back to `.env` if the
    ///   env-specific file doesn't exist.
    /// - If `ENV` is *not* set in the process env, loads `.env` first,
    ///   then re-checks `ENV` — if it resolved to a value like `prod`,
    ///   loads `.env.prod` on top to overlay environment-specific secrets.
    ///
    /// Files loaded later win (dotenvy never overwrites vars already set
    /// by the process or an earlier file), so the priority order is:
    ///   process env > `.env.{ENV}` > `.env`.
    pub fn from_env() -> anyhow::Result<Config> {
        // Check if ENV is already set in the process environment
        // (e.g. by hosting platform dashboard, CI, or shell export).
        let env_value = var("ENV").ok().filter(|v| !v.trim().is_empty());

        if let Some(ref env) = env_value {
            // ENV is known — load env-specific file, fall back to generic .env
            let env_file = format!(".env.{env}");
            if std::path::Path::new(&env_file).exists() {
                dotenvy::from_filename(&env_file).ok();
            } else {
                dotenvy::dotenv().ok();
            }
        } else {
            // ENV not set yet — load .env first so we can read ENV from it
            dotenvy::dotenv().ok();

            // Re-check: if .env defined ENV, load the env-specific file on top
            if let Ok(env) = var("ENV")
                && !env.trim().is_empty()
            {
                let env_file = format!(".env.{env}");
                if std::path::Path::new(&env_file).exists() {
                    dotenvy::from_filename(&env_file).ok();
                }
            }
        }

        Self::from_getter(|key| var(key))
    }

    /// Builds `Config` from an arbitrary var getter so tests can feed a
    /// controlled set of variables instead of mutating the process env.
    fn from_getter<F>(get: F) -> anyhow::Result<Config>
    where
        F: for<'a> Fn(&'a str) -> Result<String, VarError>,
    {
        Ok(Self {
            database_url: required(&get, "DATABASE_URL")?,
            jwt_private_key: jwt_key(&get, "JWT_PRIVATE_KEY")?,
            jwt_public_key: jwt_key(&get, "JWT_PUBLIC_KEY")?,
            smtp_host: required(&get, "SMTP_HOST")?,
            smtp_port: required(&get, "SMTP_PORT")?
                .trim()
                .parse::<u16>()
                .context("SMTP_PORT must be a valid number")?,
            smtp_user: required(&get, "SMTP_USER")?,
            smtp_password: required(&get, "SMTP_PASSWORD")?,
            smtp_from: required(&get, "SMTP_FROM")?,
            frontend_base_url: required(&get, "FRONTEND_BASE_URL")?,
            // PORT is optional (defaults to 8080). Treat a blank value the same
            // as unset — Render injects PORT automatically for web services, but
            // a `PORT=` line pasted from .env.example would otherwise crash the
            // parse below with "cannot parse integer from empty string".
            port: match get("PORT") {
                Ok(v) if !v.trim().is_empty() => v
                    .trim()
                    .parse::<u16>()
                    .context("PORT must be a valid number")?,
                _ => 8080,
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

/// Loads a JWT key (private or public) with support for both file-based and
/// inline PEM content:
///
/// - `JWT_PRIVATE_KEY_FILE` / `JWT_PUBLIC_KEY_FILE`: path to a `.pem` file
/// - `JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY`: inline PEM string (backward compat)
///
/// File-based loading takes precedence. On Render, set either the `_FILE` path
/// (if PEM files are available on disk) or paste the PEM content directly.
fn jwt_key<F>(get: &F, base_name: &str) -> anyhow::Result<String>
where
    F: for<'a> Fn(&'a str) -> Result<String, VarError>,
{
    let file_var = format!("{base_name}_FILE");

    // Try file-based loading first
    if let Ok(path) = get(&file_var) {
        let path = path.trim();
        if !path.is_empty() {
            return fs::read_to_string(path).context(format!(
                "{file_var} is set to '{path}' but the file could not be read"
            ));
        }
    }

    // Fall back to inline PEM string
    required(get, base_name)
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
            ("SMTP_HOST", "smtp.example.com"),
            ("SMTP_PORT", "587"),
            ("SMTP_USER", "test@example.com"),
            ("SMTP_PASSWORD", "test_password"),
            ("SMTP_FROM", "Test <test@example.com>"),
            ("PORT", "8080"),
            ("ENV", "dev"),
            ("R2_BUCKET", "uni-stash-images"),
            ("R2_ACCESS_KEY_ID", "test-access-key"),
            ("R2_SECRET_ACCESS_KEY", "test-secret-key"),
            ("R2_ENDPOINT", "https://r2.example.com"),
            ("FRONTEND_BASE_URL", "https://uni-stash.com"),
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
        let vars = without(&full_vars(), "SMTP_HOST");
        let err = Config::from_getter(getter(&vars)).unwrap_err();

        assert!(
            err.to_string().contains("SMTP_HOST"),
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

    #[test]
    fn blank_port_defaults_to_8080() {
        // Mirrors a `PORT=` line (empty value) — e.g. .env.example pasted into
        // Render's env vars — which used to crash with a parse error.
        for blank in ["", "   "] {
            let vars = with(&full_vars(), "PORT", blank);
            let config = Config::from_getter(getter(&vars)).unwrap();
            assert_eq!(config.port, 8080, "blank PORT should default to 8080");
        }
    }

    #[test]
    fn port_value_is_trimmed_before_parsing() {
        let vars = with(&full_vars(), "PORT", " 8081 ");
        let config = Config::from_getter(getter(&vars)).unwrap();
        assert_eq!(config.port, 8081);
    }

    #[test]
    fn jwt_key_file_loads_from_file() {
        use std::io::Write;

        // Create a temporary PEM file
        let tmp_dir = std::env::temp_dir().join("config_test");
        std::fs::create_dir_all(&tmp_dir).unwrap();
        let pem_path = tmp_dir.join("test_key.pem");
        let mut f = std::fs::File::create(&pem_path).unwrap();
        writeln!(
            f,
            "-----BEGIN PUBLIC KEY-----\nfake-key-content\n-----END PUBLIC KEY-----"
        )
        .unwrap();

        // Leak the path string so it has 'static lifetime for the test
        let path_str = Box::leak(pem_path.to_str().unwrap().to_string().into_boxed_str());
        let mut vars = full_vars();
        vars.push(("JWT_PUBLIC_KEY_FILE", path_str));
        let config = Config::from_getter(getter(&vars)).unwrap();
        assert!(
            config.jwt_public_key.contains("fake-key-content"),
            "should read from file, got: {}",
            &config.jwt_public_key
        );

        // Cleanup
        std::fs::remove_file(&pem_path).ok();
    }

    #[test]
    fn jwt_key_falls_back_to_inline_when_no_file() {
        let vars = full_vars();
        let config = Config::from_getter(getter(&vars)).unwrap();
        assert_eq!(config.jwt_private_key, "test-private-key");
    }

    #[test]
    fn jwt_key_file_not_found_returns_error() {
        let mut vars = full_vars();
        vars.push(("JWT_PRIVATE_KEY_FILE", "/nonexistent/path/key.pem"));
        let err = Config::from_getter(getter(&vars)).unwrap_err();
        assert!(
            err.to_string().contains("JWT_PRIVATE_KEY_FILE"),
            "error should mention the _FILE var, got: {err:#}"
        );
    }

    #[test]
    fn jwt_key_missing_both_file_and_inline_returns_error() {
        let vars = without(&full_vars(), "JWT_PRIVATE_KEY");
        let err = Config::from_getter(getter(&vars)).unwrap_err();
        assert!(
            err.to_string().contains("JWT_PRIVATE_KEY"),
            "error should name the missing var, got: {err:#}"
        );
    }
}
