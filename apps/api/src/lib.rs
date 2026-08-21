//! uni-stash-be — Campus Marketplace backend (see `docs/01-cm-trd.md`).
//!
//! The binary entrypoint lives in `main.rs`; everything testable lives in this
//! library crate so integration tests under `tests/` (and later feature tests)
//! can import it by name.

pub mod core;
pub mod features;
pub mod openapi;

/// `GET /health` — CM-1.7 AC 1. Returns 200 unconditionally; this endpoint
/// intentionally does not touch the DB pool or any external service — its
/// only job is proving the binary is up and routable, before any feature
/// work depends on the deploy path working.
#[actix_web::get("/health")]
pub async fn health() -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok().json(serde_json::json!({"status": "ok"}))
}

/// Registers routes shared across every deploy target (Shuttle, local
/// `main.rs`, and future integration tests) so the route list can't drift
/// between them.
pub fn configure_health(cfg: &mut actix_web::web::ServiceConfig) {
    cfg.service(health);
}

#[cfg(test)]
mod tests {
    use super::openapi::ApiDoc;
    use utoipa::OpenApi;

    /// Generate the OpenAPI spec and write it to `openapi.json` on disk.
    ///
    /// Run with: `cargo test export_openapi -- --nocapture`
    /// The file will be written to `apps/api/openapi.json`.
    #[test]
    fn export_openapi() {
        let spec = ApiDoc::openapi().to_pretty_json().unwrap();
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("openapi.json");
        std::fs::write(&path, &spec).unwrap();
        println!("OpenAPI spec written to {}", path.display());
    }
}
