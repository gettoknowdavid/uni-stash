pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/reviews",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("/{sale_id}", web::post().to(handlers::create_review))
                .route("/users/{user_id}", web::get().to(handlers::user_reviews))
                .route(
                    "/sales/{sale_id}/mine",
                    web::get().to(handlers::my_review_for_sale),
                );
        },
    );
}
