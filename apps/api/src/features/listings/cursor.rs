//! Cursor pagination for listings.
//!
//! Re-exports the shared [`crate::core::cursor`] types and provides a
//! listings-specific type alias for backward compatibility.

pub use crate::core::cursor::{Cursor as ListingCursor, decode_cursor, encode_cursor};

#[cfg(test)]
mod tests {
    // The core cursor tests cover encode/decode. Listings-specific edge cases
    // (if any) can be added here later.
}
