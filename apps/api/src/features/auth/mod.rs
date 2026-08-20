use actix_governor::{Governor, GovernorConfigBuilder, PeerIpKeyExtractor};
use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // 30 requests per minute per IP — generous enough for normal browser usage
    // (login + signup + verify-email), tight enough to blunt credential-stuffing
    // or enumeration bursts.  Built once per worker; each worker has its own
    // independent governor (actix-web design).  This is the standard pattern
    // for actix-governor — no shared static needed.
    let governor_conf = GovernorConfigBuilder::default()
        .requests_per_minute(30)
        .burst_size(30)
        .key_extractor(PeerIpKeyExtractor)
        .finish()
        .expect("valid governor config");

    cfg.service(
        web::scope("/api/v1/auth")
            .wrap(Governor::new(&governor_conf))
            .route("/signup", web::post().to(handlers::signup))
            .route("/verify-email", web::post().to(handlers::verify_email))
            .route("/login", web::post().to(handlers::login))
            .route("/refresh", web::post().to(handlers::refresh))
            .route("/logout", web::post().to(handlers::logout))
            .route("/me", web::get().to(handlers::me)),
    );
}
