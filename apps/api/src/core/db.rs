use std::time::Duration;

use crate::core::error::AppError;

#[derive(Debug)]
pub struct Db {
    pub pool: sqlx::PgPool,
}

impl Db {
    /// Connects to the PostgreSQL database using the given URL.
    ///
    /// Pool sizing is tuned for a free-tier DB (CM-1.4 AC 1): a small max, a
    /// single warm idle connection, and a short acquire timeout.
    ///
    /// The short `acquire_timeout` matters for AC 4: sqlx retries a refused/
    /// unreachable database with backoff until that deadline, so the 30s
    /// default would hang boot for half a minute before the clear fail-fast
    /// error fires. 5s bounds it.
    ///
    /// Returns a typed `AppError` instead of panicking so boot can fail fast
    /// with a clear message on connection failure.
    pub async fn connect(url: &str) -> Result<Self, AppError> {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(10)
            .min_connections(1)
            .acquire_timeout(Duration::from_secs(5))
            .connect(url)
            .await
            .map_err(|e| AppError::Internal(anyhow::anyhow!("failed to connect to {url}: {e}")))?;
        Ok(Self { pool })
    }

    /// Runs embedded database migrations.
    pub async fn run_migrations(&self) -> Result<(), AppError> {
        sqlx::migrate!()
            .run(&self.pool)
            .await
            .map_err(|e| AppError::Internal(e.into()))?;
        Ok(())
    }

    /// Returns `true` if migrations should be run based on the given environment.
    pub fn should_migrate(env: &str) -> bool {
        matches!(env, "dev" | "test")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_migrates_in_dev_and_test() {
        assert!(Db::should_migrate("dev"));
        assert!(Db::should_migrate("test"));
    }

    #[test]
    fn does_not_auto_migrate_in_prod() {
        assert!(!Db::should_migrate("prod"));
        assert!(!Db::should_migrate("production"));
    }

    #[test]
    fn unknown_env_falls_back_to_no_auto_migrate() {
        // "development" is a deliberate false — the project convention
        // (Config + .env.example) is "dev", not the longer spelling.
        assert!(!Db::should_migrate("development"));
        assert!(!Db::should_migrate("staging"));
        assert!(!Db::should_migrate(""));
    }

    #[actix_rt::test]
    async fn connect_failure_returns_err_without_panicking() {
        // Port 1 on loopback is closed on every platform, so this gets a
        // connection-refused — no live Postgres needed. The 5s acquire_timeout
        // bounds the wait (AC 4: fail fast instead of sqlx's 30s default).
        let err = Db::connect("postgres://127.0.0.1:1/uni_stash")
            .await
            .unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
    }
}
