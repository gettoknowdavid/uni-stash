//! Background job runner — periodic tasks spawned at server startup.
//!
//! Uses `tokio::spawn` + `tokio::time::interval` for zero-dependency
//! scheduling.  Each job is a named async function that runs on its own
//! interval.  The runner is composable: when the project outgrows a single
//! process (multi-worker, retries, dead-letter queues), swap the Tokio
//! tasks for `apalis` with a Postgres or Redis backend — the job *logic*
//! stays identical, only the scheduling layer changes.
//!
//! # Architecture
//!
//! ```text
//! main.rs
//!   └─ jobs::spawn(pool)
//!        ├─ cleanup_expired_tokens     (every 15 min)
//!        ├─ cleanup_old_revoked_tokens (every 1 hour)
//!        └─ ... future jobs (email scheduling, etc.)
//! ```

use sqlx::PgPool;
use tokio::time;

/// Interval between expired-token cleanup runs.
const CLEANUP_EXPIRED_INTERVAL: time::Duration = time::Duration::from_secs(15 * 60); // 15 min

/// Interval between old-revoked-token cleanup runs.
const CLEANUP_REVOKED_INTERVAL: time::Duration = time::Duration::from_secs(60 * 60); // 1 hour

/// How long to keep revoked tokens before hard-deleting them (in seconds).
/// Must be long enough for the CM-3.8 grace window (5 seconds) plus any
/// reasonable client retry window.  24 hours gives ample headroom.
const REVOKED_TOKEN_RETENTION_SECS: i64 = 24 * 60 * 60;

/// Spawns all background jobs on the current Tokio runtime.
///
/// Call once at server startup (after DB pool is ready).  Each job runs
/// independently — a panic or error in one does not affect the others.
pub fn spawn(pool: PgPool) {
    tracing::info!("spawning background jobs");

    spawn_job(
        "cleanup_expired_tokens",
        pool.clone(),
        CLEANUP_EXPIRED_INTERVAL,
        |pool| async move {
            let repo = crate::features::auth::repo::AuthRepo::new(pool);
            let deleted = repo.cleanup_expired_refresh_tokens().await?;
            if deleted > 0 {
                tracing::info!(deleted, "cleanup: deleted expired refresh tokens");
            }
            Ok::<_, anyhow::Error>(())
        },
    );

    spawn_job(
        "cleanup_old_revoked_tokens",
        pool,
        CLEANUP_REVOKED_INTERVAL,
        |pool| async move {
            let repo = crate::features::auth::repo::AuthRepo::new(pool);
            let deleted = repo
                .cleanup_old_revoked_tokens(REVOKED_TOKEN_RETENTION_SECS)
                .await?;
            if deleted > 0 {
                tracing::info!(deleted, "cleanup: deleted old revoked refresh tokens");
            }
            Ok::<_, anyhow::Error>(())
        },
    );
}

/// Spawn a single named job that runs `f(pool)` on a fixed interval.
///
/// The first iteration runs immediately (via `interval.tick().await` which
/// resolves on the first call), then repeats every `interval`.  Errors
/// are logged but do not crash the job — it continues on the next tick.
fn spawn_job<F, Fut>(name: &str, pool: PgPool, interval: time::Duration, f: F)
where
    F: Fn(PgPool) -> Fut + Send + 'static,
    Fut: std::future::Future<Output = Result<(), anyhow::Error>> + Send + 'static,
{
    tracing::debug!(job = %name, interval_secs = interval.as_secs(), "background job registered");

    let name = name.to_string();
    tokio::spawn(async move {
        let mut ticker = time::interval(interval);
        ticker.set_missed_tick_behavior(time::MissedTickBehavior::Delay);

        // First tick fires immediately — run once at startup.
        ticker.tick().await;

        loop {
            if let Err(e) = f(pool.clone()).await {
                tracing::error!(job = %name, "background job failed: {e:#}");
            }
            ticker.tick().await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleanup_intervals_are_sane() {
        // Expired cleanup should run at least every 30 min.
        assert!(
            CLEANUP_EXPIRED_INTERVAL <= time::Duration::from_secs(30 * 60),
            "expired cleanup interval too long: {:?}",
            CLEANUP_EXPIRED_INTERVAL
        );
        // Revoked retention should be at least 1 hour (grace window safety).
        assert!(
            REVOKED_TOKEN_RETENTION_SECS >= 3600,
            "revoked retention too short: {}s",
            REVOKED_TOKEN_RETENTION_SECS
        );
        // Revoked cleanup interval should be <= retention.
        assert!(
            CLEANUP_REVOKED_INTERVAL
                <= time::Duration::from_secs(REVOKED_TOKEN_RETENTION_SECS as u64),
            "revoked cleanup runs less often than retention period"
        );
    }
}
