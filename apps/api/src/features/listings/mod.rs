use actix_web::web;

pub mod cursor;
pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;
pub mod state_machine;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/listings",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                // CM-4.1 — Create
                .route("", web::post().to(handlers::create_listing))
                // CM-4.2 — Browse
                .route("", web::get().to(handlers::list_listings))
                // CM-4.3 — Detail
                .route("/{id}", web::get().to(handlers::get_listing_detail))
                // CM-4.4 — Edit
                .route("/{id}", web::patch().to(handlers::update_listing))
                // CM-4.5 — Soft delete
                .route("/{id}", web::delete().to(handlers::delete_listing))
                // CM-4.6 — Reserve
                .route("/{id}/reserve", web::post().to(handlers::reserve_listing))
                // CM-4.7 — Mark sold / Unreserve
                .route("/{id}/mark-sold", web::post().to(handlers::mark_sold))
                .route(
                    "/{id}/unreserve",
                    web::post().to(handlers::unreserve_listing),
                );
        },
    );
}
