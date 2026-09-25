pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/notifications",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route(
                    "/register-device",
                    web::post().to(handlers::register_device),
                )
                .route("/", web::get().to(handlers::list_notifications))
                .route(
                    "/unread-count",
                    web::get().to(handlers::unread_count),
                )
                .route(
                    "/{id}/read",
                    web::post().to(handlers::mark_read),
                )
                .route(
                    "/read-all",
                    web::post().to(handlers::mark_all_read),
                )
                .route(
                    "/{id}",
                    web::delete().to(handlers::delete_notification),
                );
        },
    );
}
