pub mod dtos;
pub mod handlers;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/users",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            // /{user_id}/listings must come before /{user_id} for matching
            // clarity, though actix matches by specificity here anyway.
            scope
                .route(
                    "/{user_id}/listings",
                    web::get().to(handlers::user_listings),
                )
                .route("/{user_id}", web::get().to(handlers::get_profile));
        },
    );
}
