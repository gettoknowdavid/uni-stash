use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod repo;

pub use repo::AdminManagementRepo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // Admin management endpoints: reuse the same rate limit as admin auth.
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/admin",
        crate::core::governor::AUTH_RATE_LIMIT,
        |scope| {
            scope
                .route("/admins", web::post().to(handlers::create_admin))
                .route("/admins", web::get().to(handlers::list_admins))
                .route("/admins/{id}", web::patch().to(handlers::update_admin))
                .route("/admins/{id}", web::delete().to(handlers::deactivate_admin));
        },
    );
}
