use actix_web::web;

pub mod dtos;
pub mod handlers;
pub mod models;
pub mod repo;

pub fn configure(cfg: &mut web::ServiceConfig) {
    // Auth endpoints: 10 req/min per IP (TRD §2.5.1).
    // Tighter than general endpoints — blunt credential-stuffing and
    // user-enumeration bursts.  Combined with the per-email limiter
    // (core::rate_limit::PerEmailLimiter), an attacker can't route around
    // the IP-based limit by rotating source addresses, nor route around
    // the email-based limit by spraying many emails from one IP.
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/auth",
        crate::core::governor::AUTH_RATE_LIMIT,
        |scope| {
            scope
                .route("/signup", web::post().to(handlers::signup))
                .route("/verify-otp", web::post().to(handlers::verify_otp))
                .route(
                    "/resend-verification",
                    web::post().to(handlers::resend_verification),
                )
                .route(
                    "/forgot-password",
                    web::post().to(handlers::forgot_password),
                )
                .route("/reset-password", web::post().to(handlers::reset_password))
                .route("/login", web::post().to(handlers::login))
                .route("/refresh", web::post().to(handlers::refresh))
                .route("/logout", web::post().to(handlers::logout))
                .route("/me", web::get().to(handlers::me));
        },
    );
}
