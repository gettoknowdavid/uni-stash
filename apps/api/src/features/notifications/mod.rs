pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/notifications",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope.route(
                "/register-device",
                web::post().to(handlers::register_device),
            );
        },
    );
}
