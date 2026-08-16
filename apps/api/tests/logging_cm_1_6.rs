// apps/api/tests/logging_cm_1_6.rs
//
// CM-1.6 integration verification: boots the real `App` with the real
// `logging::http_middleware()`, fires a request through it, and asserts the
// captured log line carries method, path, status, latency, and a request id.
//
// The global subscriber is installed exactly once (the whole test binary only
// runs this file), and events are captured into an in-memory buffer so the
// assertion inspects the actual formatted output, not a mocked middleware.

use std::io::Write;
use std::sync::{Arc, Mutex, OnceLock};

use actix_web::{App, HttpResponse, test, web};
use uni_stash_be::core::logging;

/// Shared capture buffer for whatever the global subscriber writes.
static LOGS: OnceLock<Arc<Mutex<Vec<u8>>>> = OnceLock::new();

fn logs() -> Arc<Mutex<Vec<u8>>> {
    LOGS.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
        .clone()
}

/// A `MakeWriter` that appends every formatted line into `LOGS`.
#[derive(Clone, Copy)]
struct Capture;

impl Write for Capture {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        logs().lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl tracing_subscriber::fmt::MakeWriter<'_> for Capture {
    type Writer = Capture;
    fn make_writer(&self) -> Self::Writer {
        Capture
    }
}

#[actix_web::test]
async fn request_log_line_has_method_path_status_latency_and_request_id() {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        tracing_subscriber::fmt()
            .with_writer(Capture)
            .with_ansi(false)
            .with_target(false)
            .with_max_level(tracing::Level::INFO)
            .compact()
            .init();
    });

    let app = test::init_service(App::new().wrap(logging::http_middleware()).route(
        "/health",
        web::get().to(|| async { HttpResponse::Ok().finish() }),
    ))
    .await;

    let resp = test::call_service(&app, test::TestRequest::get().uri("/health").to_request()).await;
    assert_eq!(resp.status(), 200);

    // The response event is recorded synchronously as the response future
    // resolves; give the writer a beat to flush everything into the buffer.
    std::thread::sleep(std::time::Duration::from_millis(50));

    let output = String::from_utf8(logs().lock().unwrap().clone()).unwrap();
    assert!(
        output.contains("http.method=GET"),
        "method missing from log line: {output}"
    );
    assert!(
        output.contains("http.target=/health"),
        "path missing from log line: {output}"
    );
    assert!(
        output.contains("http.status_code=200"),
        "status missing from log line: {output}"
    );
    assert!(
        output.contains("latency"),
        "latency missing from log line: {output}"
    );
    assert!(
        output.contains("request_id"),
        "request id missing from log line: {output}"
    );
}
