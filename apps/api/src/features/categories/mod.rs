use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/categories",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope.route("", web::get().to(handlers::list_categories));
        },
    );
}
