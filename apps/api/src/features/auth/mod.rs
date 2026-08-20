use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/auth")
            .route("/signup", web::post().to(handlers::signup))
            .route("verify-email", web::post().to(handlers::verify_email)),
    );
}
