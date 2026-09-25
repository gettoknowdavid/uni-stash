pub mod handlers;
pub mod repo;

use actix_web::web;

pub fn configure(cfg: &mut web::ServiceConfig) {
    crate::core::governor::apply_rate_limit(
        cfg,
        "/api/v1/blocks",
        crate::core::governor::LISTINGS_RATE_LIMIT,
        |scope| {
            scope
                // /mine must come before /{user_id}.
                .route("/mine", web::get().to(handlers::list_blocked))
                .route("/{user_id}", web::post().to(handlers::block_user))
                .route("/{user_id}", web::delete().to(handlers::unblock_user));
        },
    );
}
