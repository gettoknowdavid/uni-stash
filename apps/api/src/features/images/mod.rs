pub mod dtos;
pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/images")
            // CM-6.1 — Presign a PUT URL for direct client upload
            .route("/presign", web::post().to(handlers::presign_image))
            // CM-6.2 — Confirm upload landed in B2, register in DB
            .route("/confirm", web::post().to(handlers::confirm_image))
            // CM-6.3 — Delete image (owner-only)
            .route("/{id}", web::delete().to(handlers::delete_image)),
    );
}
