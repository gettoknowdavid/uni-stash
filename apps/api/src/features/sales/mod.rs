pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/sales",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("/purchases", web::get().to(handlers::my_purchases))
                .route("/mine", web::get().to(handlers::my_sales));
        },
    );
}
