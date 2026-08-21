use actix_web::web;

pub mod cursor;
pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/listings",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("", web::post().to(handlers::create_listing))
                .route("", web::get().to(handlers::list_listings));
        },
    );
}
