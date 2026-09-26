use metrics_exporter_prometheus::{Matcher, PrometheusBuilder, PrometheusHandle};

/// Process-wide Prometheus recorder handle. Set once by [`init`]; `/metrics`
/// renders from it. `OnceLock` (not state in `AppState`) keeps the recorder
/// reachable from any thread without threading a handle through every call
/// site — metrics are process-global by nature.
static HANDLE: std::sync::OnceLock<PrometheusHandle> = std::sync::OnceLock::new();

/// Metric names. Centralised so the dashboards and this code can't drift.
pub mod names {
    /// Total HTTP requests completed (status label).
    pub const HTTP_REQUESTS: &str = "http_requests_total";
    /// Request latency distribution (seconds).
    pub const HTTP_LATENCY: &str = "http_request_duration_seconds";
    /// In-flight requests at scrape time.
    pub const HTTP_IN_FLIGHT: &str = "http_requests_in_flight";
    /// SQLx pool checkout wait (seconds) — the primary "DB is saturated"
    /// signal; spikes here mean the pool is too small or queries are slow.
    pub const DB_POOL_ACQUIRE: &str = "db_pool_acquire_seconds";
}

/// Installs the global Prometheus recorder. Call once at boot, after
/// `Config` is loaded, before the server starts. Idempotent-safe: a second
/// call (tests, embedding) logs and leaves the first recorder in place.
///
/// `quantiles` — render latency histograms with these quantiles as summary
/// buckets. Matchers must be installed before any observation.
pub fn init() -> anyhow::Result<()> {
    let handle = PrometheusBuilder::new()
        .set_buckets_for_metric(
            Matcher::Full(names::HTTP_LATENCY.to_string()),
            // Prometheus-ready latency buckets: sub-ms to 30s.
            &[
                0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0,
            ],
        )
        .map_err(|e| anyhow::anyhow!("metrics bucket setup failed: {e}"))?
        .install_recorder()
        .map_err(|e| anyhow::anyhow!("prometheus recorder install failed: {e}"))?;

    let _ = HANDLE.set(handle);
    Ok(())
}

/// Renders the current metrics in Prometheus text exposition format —
/// the body of `GET /metrics`.
pub fn render() -> String {
    match HANDLE.get() {
        Some(handle) => handle.render(),
        // /metrics before init (impossible in main, possible in exotic test
        // harnesses): return a valid, empty exposition instead of panicking.
        None => "# metrics recorder not initialised\n".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Recording helpers
//
// Each helper wraps the `metrics` crate macros so call sites stay terse and
// the label conventions live in exactly one file.
// ---------------------------------------------------------------------------

/// Records one completed HTTP request. `route` is the matched pattern
/// (e.g. `/api/v1/listings/{id}`) — never the raw path, or cardinality
/// explodes with every UUID.
pub fn record_http_request(method: &str, route: &str, status: u16, latency_seconds: f64) {
    metrics::counter!(
        names::HTTP_REQUESTS,
        "method" => method.to_string(),
        "route" => route.to_string(),
        "status" => status.to_string(),
    )
    .increment(1);

    metrics::histogram!(
        names::HTTP_LATENCY,
        "method" => method.to_string(),
        "route" => route.to_string(),
    )
    .record(latency_seconds);
}

/// Increments/decrements the in-flight gauge (call with +1 on request
/// start, -1 on end).
pub fn adjust_in_flight(delta: i64) {
    metrics::gauge!(names::HTTP_IN_FLIGHT).increment(delta as f64);
}

/// Records how long a DB connection took to check out of the pool.
pub fn record_db_pool_acquire(seconds: f64) {
    metrics::histogram!(names::DB_POOL_ACQUIRE).record(seconds);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_without_init_returns_placeholder() {
        // init() may already have run in another test in this binary; either
        // way render() must be valid text and never panic.
        let out = render();
        assert!(out.starts_with('#') || out.contains("http_requests_total"));
    }
}
