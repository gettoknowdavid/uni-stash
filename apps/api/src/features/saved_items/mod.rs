pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/saved-items",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("", web::get().to(handlers::list_saved))
                .route("/{id}", web::post().to(handlers::save_item))
                .route("/{id}", web::delete().to(handlers::unsave_item))
                .route("/{id}/status", web::get().to(handlers::item_status));
        },
    );
}
