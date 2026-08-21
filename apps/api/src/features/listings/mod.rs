use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // Listings: 30 req/min per IP — generous enough for legitimate usage
    // (browsing + creating), tight enough to cap automated scraping/abuse.
    // The create endpoint also validates email_verified at the handler level.
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/listings",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope.route("", web::post().to(handlers::create_listing));
        },
    );
}
