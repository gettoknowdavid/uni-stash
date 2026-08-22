use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub use repo::AdminAuthRepo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // Admin auth endpoints: same rate limit as student auth (10 req/min per IP).
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/admin/auth",
        crate::core::governor::AUTH_RATE_LIMIT,
        |scope| {
            scope
                .route("/login", web::post().to(handlers::login))
                .route("/refresh", web::post().to(handlers::refresh))
                .route("/logout", web::post().to(handlers::logout))
                .route("/me", web::get().to(handlers::me))
                .route(
                    "/forgot-password",
                    web::post().to(handlers::forgot_password),
                )
                .route("/reset-password", web::post().to(handlers::reset_password));
        },
    );
}
