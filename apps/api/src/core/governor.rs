use actix_governor::{Governor, GovernorConfigBuilder, PeerIpKeyExtractor};
use actix_web::web;

/// Per-IP rate limit configuration for use with `actix_governor`.
///
/// Auth endpoints use a tighter limit (10 req/min, per TRD §2.5.1) to blunt
/// credential-stuffing and user-enumeration bursts.  Listings and other
/// read-heavy endpoints get a more generous 30 req/min.
pub struct RateLimitConfig {
    pub requests_per_minute: u64,
    pub burst_size: u32,
}

/// Auth endpoints: 10 req/min per IP.
pub const AUTH_RATE_LIMIT: RateLimitConfig = RateLimitConfig {
    requests_per_minute: 10,
    burst_size: 10,
};

/// Listings (and other general mutating endpoints): 30 req/min per IP.
///
/// The listings create path is lower-risk than auth — creating a listing
/// doesn't expose credentials or enable account takeover — so 30 req/min
/// is generous enough for legitimate usage while still capping abuse.
/// This limit was deliberately chosen (see CM-12.1 audit notes); the
/// per-user listing cap will be enforced at the DB/business-logic level
/// in a later ticket.
pub const LISTINGS_RATE_LIMIT: RateLimitConfig = RateLimitConfig {
    requests_per_minute: 30,
    burst_size: 30,
};

/// Build an `actix-governor` middleware scoped to the given path prefix
/// with the specified rate limit config.  The `routes` callback receives
/// the inner scope so the caller can add routes to it.
///
/// # Example
///
/// ```ignore
/// crate::core::governor::apply_rate_limit(
///     cfg,
///     "/api/v1/auth",
///     crate::core::governor::AUTH_RATE_LIMIT,
///     |scope| {
///         scope
///             .route("/login", web::post().to(handlers::login));
///     },
/// );
/// ```
pub fn apply_rate_limit<F>(
    cfg: &mut web::ServiceConfig,
    path: &str,
    config: RateLimitConfig,
    routes: F,
) where
    F: FnOnce(&mut web::ServiceConfig) + 'static,
{
    let governor_conf = GovernorConfigBuilder::default()
        .requests_per_minute(config.requests_per_minute)
        .burst_size(config.burst_size)
        .key_extractor(PeerIpKeyExtractor)
        .finish()
        .expect("valid governor config");

    cfg.service(
        web::scope(path)
            .wrap(Governor::new(&governor_conf))
            .configure(routes),
    );
}
