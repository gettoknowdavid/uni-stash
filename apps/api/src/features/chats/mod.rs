pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/chats",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("", web::post().to(handlers::create_chat))
                .route("", web::get().to(handlers::list_chats))
                .route("/{id}/messages", web::get().to(handlers::list_messages))
                .route("/{id}/messages", web::post().to(handlers::send_message))
                .route("/{id}/read", web::post().to(handlers::mark_read));
        },
    );

    // Realtime channel auth is a distinct path (no rate-limit coupling with
    // chats); it requires AuthUser and validates chat participation.
    cfg.service(
        web::scope("/api/v1/realtime").route("/auth", web::post().to(handlers::realtime_auth)),
    );
}
