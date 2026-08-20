//! External service clients that back [`AppState`](super::state::AppState).
//!
//! Each client wraps an `Arc`-backed inner type so cloning is cheap (pointer
//! bumps only). Construction happens once at boot inside `AppState::new`.

mod jwt;
mod r2;
mod resend;

pub use jwt::JwtKeys;
pub use r2::R2Client;
pub use resend::ResendClient;
