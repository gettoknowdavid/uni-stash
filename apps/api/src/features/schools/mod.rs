use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // Rate-limit the entire schools scope. GET endpoints are read-only and
    // cheap, but the scope-wide limit (30 req/min per IP, same as listings)
    // is generous enough to not be a problem for legitimate read traffic.
    // This avoids the complexity of mixing scoped and unscoped routes on the
    // same path prefix.
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/schools",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("", web::get().to(handlers::list_schools))
                .route("/{id}", web::get().to(handlers::get_school))
                .route("", web::post().to(handlers::create_school))
                .route("/{id}", web::patch().to(handlers::update_school))
                .route("/{id}", web::delete().to(handlers::delete_school));
        },
    );
}
