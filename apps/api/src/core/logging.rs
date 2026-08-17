use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use actix_web::Error;
use actix_web::body::MessageBody;
use actix_web::dev::{ServiceRequest, ServiceResponse};
use tracing::Span;
use tracing_actix_web::{DefaultRootSpanBuilder, RootSpanBuilder, TracingLogger};
use tracing_subscriber::EnvFilter;

/// Installs the global tracing setup. Call once, at boot, after `Config` is
/// loaded. Logging setup is best-effort and must never crash boot: if a
/// subscriber or `log` logger is already installed (e.g. an embedding binary
/// or test harness), degrade to a warning instead of panicking.
pub fn init(env: &str) {
    let filter = filter();

    // Install the fmt subscriber FIRST. When the `tracing-log` feature is
    // compiled in (enabled transitively today), `try_init` also installs a
    // `LogTracer` bridging `log`-crate records (actix-server, actix-web
    // internals) into tracing. Installing our own LogTracer before this call
    // used to panic: fmt's `.init()` attempts a second LogTracer install,
    // gets `SetLoggerError`, and treats it as fatal.
    //
    // prod: machine-readable JSON for log aggregation; dev/test: compact lines.
    // Span fields are inlined into event lines by default (`with_current_span`).
    let result = if env == "prod" {
        tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(false)
            .json()
            .try_init()
    } else {
        tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(false)
            .compact()
            .try_init()
    };

    if let Err(err) = result {
        eprintln!("warning: failed to install global tracing subscriber: {err}");
    }

    // Belt-and-suspenders for builds without the `tracing-log` feature: route
    // `log`-crate records into tracing so nothing is split across two logging
    // systems. No-op when the fmt subscriber already installed one.
    let _ = tracing_log::LogTracer::init();

    install_panic_hook();
}

/// Logs any panic (request handler, background task, worker thread) with the
/// full panic message + location. Without this, actix-web turns a handler
/// panic into a silent 500 with no server-side breadcrumb.
///
/// Note: `PanicHookInfo`'s `Debug` impl hides the payload (`payload: Any { .. }`),
/// so the message has to be pulled out via `payload().downcast_ref`.
fn install_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        let message = info
            .payload()
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| info.payload().downcast_ref::<String>().map(String::as_str))
            .unwrap_or("non-string panic payload");
        tracing::error!(
            target: "panic",
            message,
            panic_location = ?info.location(),
            "thread panicked"
        );
    }));
}

/// RUST_LOG if set, otherwise a sane default. `EnvFilter::try_from_default_env`
/// reads RUST_LOG; an unset/empty value falls back to INFO everywhere.
fn filter() -> EnvFilter {
    EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"))
}

/// Per-request start times, keyed by span id, so the canonical log line can
/// report latency. Entries are removed when the response completes; only
/// requests aborted mid-flight can leave one behind (bounded by the number of
/// concurrent in-flight requests).
static STARTS: OnceLock<Mutex<HashMap<tracing::Id, Instant>>> = OnceLock::new();

fn starts() -> &'static Mutex<HashMap<tracing::Id, Instant>> {
    STARTS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Root span builder that layers `latency_ms` and a canonical per-request log
/// line on top of the stock HTTP fields.
///
/// Why a custom builder: the stock `TracingLogger` records method, path,
/// status, and request id onto the span but never emits a log line for a
/// successful request — a healthy request would be invisible in the logs. This
/// builder delegates to `DefaultRootSpanBuilder` for the standard fields (the
/// crate's documented composition pattern), then records latency and emits one
/// line per request. That event is created inside the root span, so the
/// formatter inlines every span field into the line: method, path, status,
/// latency, and request id.
pub struct RequestRootSpanBuilder;

impl RootSpanBuilder for RequestRootSpanBuilder {
    fn on_request_start(request: &ServiceRequest) -> Span {
        // `latency_ms` must be declared here or `span.record` silently drops it.
        let span = tracing_actix_web::root_span!(request, latency_ms = tracing::field::Empty);
        if let Some(id) = span.id() {
            starts().lock().unwrap().insert(id, Instant::now());
        }
        span
    }

    fn on_request_end<B: MessageBody>(span: Span, outcome: &Result<ServiceResponse<B>, Error>) {
        // http.status_code, otel.status_code, and exception.* fields — same as
        // the stock builder.
        DefaultRootSpanBuilder::on_request_end(span.clone(), outcome);

        let latency_ms = span
            .id()
            .and_then(|id| starts().lock().unwrap().remove(&id))
            .map(|t0| t0.elapsed().as_millis() as i64)
            .unwrap_or(-1);
        span.record("latency_ms", latency_ms);

        // The canonical line: emitted inside the root span, so the formatter
        // attaches http.method/http.target/http.status_code/request_id/latency_ms.
        tracing::info!("request completed");
    }
}

/// The request-scoped tracing middleware, registered outermost on the `App`
/// (first `wrap()` call in `main.rs` → top of the middleware stack, per the
/// ticket's "wrap early" note).
pub fn http_middleware() -> TracingLogger<RequestRootSpanBuilder> {
    TracingLogger::new()
}

#[cfg(test)]
mod tests {
    use std::panic::{AssertUnwindSafe, catch_unwind};
    use std::sync::{Arc, Mutex};

    use super::*;

    /// A `MakeWriter` that captures formatted output in memory.
    #[derive(Clone, Default)]
    struct SharedWriter(Arc<Mutex<Vec<u8>>>);

    impl std::io::Write for SharedWriter {
        fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    impl tracing_subscriber::fmt::MakeWriter<'_> for SharedWriter {
        type Writer = SharedWriter;
        fn make_writer(&self) -> Self::Writer {
            self.clone()
        }
    }

    #[test]
    fn panic_hook_logs_payload_and_location() {
        install_panic_hook();

        let logs = SharedWriter::default();
        let subscriber = tracing_subscriber::fmt()
            .with_writer(logs.clone())
            .with_ansi(false)
            .with_target(false)
            .compact()
            .finish();

        // The hook fires on the panicking thread, so a thread-local default
        // subscriber captures it without touching the process-global one.
        tracing::subscriber::with_default(subscriber, || {
            let result = catch_unwind(AssertUnwindSafe(|| panic!("db exploded")));
            assert!(result.is_err(), "expected the panic to unwind");
        });

        let output = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
        assert!(
            output.contains("db exploded"),
            "panic payload missing from log: {output}"
        );
        assert!(
            output.contains("thread panicked"),
            "panic hook message missing from log: {output}"
        );
    }

    #[test]
    fn env_filter_construction_never_fails() {
        // Guards the fallback path: an unset RUST_LOG must still produce a
        // valid, usable EnvFilter (can't assert the exact value here without
        // mutating process env, which is racy across parallel tests).
        let _ = filter();
    }
}
