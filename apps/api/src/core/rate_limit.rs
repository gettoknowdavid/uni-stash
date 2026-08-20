use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::Instant;

use crate::core::error::AppError;

/// Sliding-window per-email rate limiter.
///
/// Lightweight in-memory implementation — sufficient for solo-dev / MVP scale.
/// `actix-governor`'s `KeyExtractor` only sees the `ServiceRequest`, not the
/// parsed JSON body, so per-email limiting cannot be cleanly done via governor.
/// This explicit check runs after deserialization but before any DB work.
///
/// The limiter is `Clone` (via `Arc`) and safe to share across async tasks.
#[derive(Clone)]
pub struct PerEmailLimiter {
    inner: std::sync::Arc<Mutex<Inner>>,
}

struct Inner {
    /// Lowercased email → deque of request timestamps within the window.
    windows: std::collections::HashMap<String, VecDeque<Instant>>,
}

/// Default: 30 requests per 60-second sliding window.
const DEFAULT_MAX_REQUESTS: usize = 30;
const WINDOW_SECS: u64 = 60;

impl PerEmailLimiter {
    /// Creates a limiter with the default limits (30 req / 60 s).
    pub fn new() -> Self {
        Self {
            inner: std::sync::Arc::new(Mutex::new(Inner {
                windows: std::collections::HashMap::new(),
            })),
        }
    }

    /// Check whether `email` is within the rate limit.
    ///
    /// Returns `Ok(())` if the request is allowed, or `Err(AppError::TooManyRequests)`
    /// if the window is exhausted.  The check is idempotent — calling it does NOT
    /// consume a slot; the caller must call [`record`](Self::record) separately
    /// after a successful operation, or call [`check_and_record`](Self::check_and_record)
    /// to do both atomically.
    pub fn check(&self, email: &str) -> Result<(), AppError> {
        let key = email.to_lowercase();
        let mut inner = self.inner.lock().expect("rate limiter lock poisoned");
        let now = Instant::now();
        let window = inner.windows.entry(key).or_default();

        // Evict entries older than the window.
        while window
            .front()
            .is_some_and(|t| now.duration_since(*t).as_secs() >= WINDOW_SECS)
        {
            window.pop_front();
        }

        if window.len() >= DEFAULT_MAX_REQUESTS {
            return Err(AppError::TooManyRequests);
        }

        Ok(())
    }

    /// Atomically check and record a request for `email`.
    ///
    /// Convenience wrapper that combines [`check`](Self::check) + [`record`](Self::record).
    pub fn check_and_record(&self, email: &str) -> Result<(), AppError> {
        self.check(email)?;
        self.record(email);
        Ok(())
    }

    /// Record a successful request for `email` without checking.
    ///
    /// Call this after the operation succeeds if you used [`check`](Self::check)
    /// separately.
    pub fn record(&self, email: &str) {
        let key = email.to_lowercase();
        let mut inner = self.inner.lock().expect("rate limiter lock poisoned");
        let now = Instant::now();
        let window = inner.windows.entry(key).or_default();

        // Evict stale entries before recording.
        while window
            .front()
            .is_some_and(|t| now.duration_since(*t).as_secs() >= WINDOW_SECS)
        {
            window.pop_front();
        }

        window.push_back(now);
    }
}

impl Default for PerEmailLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Debug for PerEmailLimiter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PerEmailLimiter")
            .field("window_secs", &WINDOW_SECS)
            .field("max_requests", &DEFAULT_MAX_REQUESTS)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_requests_under_limit() {
        let limiter = PerEmailLimiter::new();
        for _ in 0..DEFAULT_MAX_REQUESTS {
            limiter.check_and_record("alice@test.edu").unwrap();
        }
        // The very next one should be rejected.
        assert!(limiter.check("alice@test.edu").is_err());
    }

    #[test]
    fn rejects_after_limit_reached() {
        let limiter = PerEmailLimiter::new();
        for _ in 0..DEFAULT_MAX_REQUESTS {
            limiter.check_and_record("bob@test.edu").unwrap();
        }
        assert!(matches!(
            limiter.check("bob@test.edu"),
            Err(AppError::TooManyRequests)
        ));
    }

    #[test]
    fn different_emails_are_independent() {
        let limiter = PerEmailLimiter::new();
        for _ in 0..DEFAULT_MAX_REQUESTS {
            limiter.check_and_record("alice@test.edu").unwrap();
        }
        // Alice is exhausted, but Bob is fine.
        assert!(limiter.check("alice@test.edu").is_err());
        limiter.check_and_record("bob@test.edu").unwrap();
    }

    #[test]
    fn email_is_case_insensitive() {
        let limiter = PerEmailLimiter::new();
        for _ in 0..DEFAULT_MAX_REQUESTS {
            limiter.check_and_record("Alice@Test.EDU").unwrap();
        }
        // Same email in different case should also be exhausted.
        assert!(limiter.check("alice@test.edu").is_err());
    }

    #[test]
    fn record_without_check_works() {
        let limiter = PerEmailLimiter::new();
        limiter.record("carol@test.edu");
        assert!(limiter.check("carol@test.edu").is_ok());
    }
}
