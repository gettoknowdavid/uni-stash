//! Email helpers for the auth feature.
//!
//! The core `send_verification_email` implementation lives on
//! [`ResendClient::send_verification_email`](crate::core::state::ResendClient)
//! since it needs access to the HTTP client and API key. This module exists as
//! the future home of auth-specific email formatting or template helpers.
