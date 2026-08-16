//! uni-stash-be — Campus Marketplace backend (see `docs/01-cm-trd.md`).
//!
//! The binary entrypoint lives in `main.rs`; everything testable lives in this
//! library crate so integration tests under `tests/` (and later feature tests)
//! can import it by name.

pub mod core;
