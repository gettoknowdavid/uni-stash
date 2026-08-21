use actix_governor::{Governor, GovernorConfigBuilder, PeerIpKeyExtractor};
use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    let governor_conf = GovernorConfigBuilder::default()
        .requests_per_minute(30)
        .burst_size(30)
        .key_extractor(PeerIpKeyExtractor)
        .finish()
        .expect("valid governor config");

    cfg.service(
        web::scope("/api/v1/listings")
            .wrap(Governor::new(&governor_conf))
            .route("", web::post().to(handlers::create_listing)),
    );
}
