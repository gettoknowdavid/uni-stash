use serde::Serialize;

pub mod handlers;
pub mod repo;

use actix_web::web;

#[derive(Serialize)]
pub struct ReportsListResponse {
    pub reports: Vec<repo::ReportResponse>,
    pub next_cursor: Option<String>,
}

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/reports",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                .route("/{listing_id}", web::post().to(handlers::create_report))
                .route("/{report_id}", web::patch().to(handlers::update_report))
                .route("/{report_id}", web::delete().to(handlers::delete_report))
                .route("/mine", web::get().to(handlers::my_reports));
        },
    );
}
