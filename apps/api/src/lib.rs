//! uni-stash-be — Campus Marketplace backend (see `docs/01-cm-trd.md`).
//!
//! The binary entrypoint lives in `main.rs`; everything testable lives in this
//! library crate so integration tests under `tests/` (and later feature tests)
//! can import it by name.

pub mod core;
pub mod features;

/// `GET /health` — CM-1.7 AC 1. Returns 200 unconditionally; this endpoint
/// intentionally does not touch the DB pool or any external service — its
/// only job is proving the binary is up and routable, before any feature
/// work depends on the deploy path working.
#[actix_web::get("/health")]
pub async fn health() -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok()
        .json(core::response::ApiResponse::<(), core::response::ErrorBody>::success((), "ok"))
}

/// `GET /metrics` — Prometheus scrape endpoint (text exposition format).
///
/// Guarded by the app's own metrics config: `METRICS_ENABLED=false` → 404;
/// a set `METRICS_TOKEN` requires `Authorization: Bearer <token>`. The
/// endpoint sits outside the v1 API and skips the auth middleware — scraper
/// access is controlled by network topology (private Render port) plus the
/// optional bearer token, not user JWTs.
#[actix_web::get("/metrics")]
pub async fn metrics_endpoint(
    config: actix_web::web::Data<core::config::Config>,
    req: actix_web::HttpRequest,
) -> actix_web::HttpResponse {
    if !config.metrics_enabled {
        return actix_web::HttpResponse::NotFound().finish();
    }

    if !config.metrics_token.is_empty() {
        let expected = format!("Bearer {}", config.metrics_token);
        let ok = req
            .headers()
            .get(actix_web::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|v| v == expected);
        if !ok {
            return actix_web::HttpResponse::Unauthorized().finish();
        }
    }

    actix_web::HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4; charset=utf-8")
        .body(core::metrics::render())
}

/// Registers routes shared across every deploy target (Shuttle, local
/// `main.rs`, and future integration tests) so the route list can't drift
/// between them.
pub fn configure_health(cfg: &mut actix_web::web::ServiceConfig) {
    cfg.service(health);
    cfg.service(metrics_endpoint);
}
