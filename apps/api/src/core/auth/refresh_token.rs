use sha2::{Digest, Sha256};

/// Refresh-token TTL in days. Lives inside the TRD §2.5.1 14–30 day range;
/// 21 days gives a 3-week sliding window before inactive sessions expire.
pub const REFRESH_TOKEN_TTL_DAYS: i64 = 21;

/// Generates a high-entropy opaque refresh token: 32 random bytes (256 bits)
/// via the thread-local CSPRNG (seeded from the OS entropy source),
/// hex-encoded into a 64-character string.
///
/// The raw value is handed to the client and **never** stored. Only its
/// SHA-256 hash is persisted (see [`hash_refresh_token`]).
pub fn generate_refresh_token_plain() -> String {
    let bytes: [u8; 32] = rand::random();
    hex::encode(bytes)
}

/// One-way SHA-256 hash of the opaque refresh token.
///
/// SHA-256 (not Argon2) is correct here per TRD §2.5.1: the token is already
/// high-entropy, so the slow KDF used on user passwords is unnecessary overhead.
/// A DB leak (backup exposure, misconfigured replica, etc.) does not hand out
/// usable refresh tokens.
pub fn hash_refresh_token(plain: &str) -> String {
    let hash = Sha256::digest(plain.as_bytes());
    hex::encode(hash)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_produces_64_char_hex_string() {
        let token = generate_refresh_token_plain();
        assert_eq!(token.len(), 64, "32 bytes hex-encoded must be 64 chars");
        assert!(
            token.chars().all(|c| c.is_ascii_hexdigit()),
            "token must be valid hex: {token}"
        );
    }

    #[test]
    fn two_calls_produce_different_tokens() {
        let a = generate_refresh_token_plain();
        let b = generate_refresh_token_plain();
        assert_ne!(
            a, b,
            "CSPRNG must not produce identical tokens consecutively"
        );
    }

    #[test]
    fn hash_is_deterministic() {
        let plain = generate_refresh_token_plain();
        let h1 = hash_refresh_token(&plain);
        let h2 = hash_refresh_token(&plain);
        assert_eq!(h1, h2, "hash must be deterministic for the same input");
    }

    #[test]
    fn hash_is_64_char_hex() {
        let hash = hash_refresh_token("some-token");
        assert_eq!(hash.len(), 64, "SHA-256 hex must be 64 chars");
        assert!(
            hash.chars().all(|c| c.is_ascii_hexdigit()),
            "hash must be valid hex: {hash}"
        );
    }

    #[test]
    fn hash_differs_for_different_inputs() {
        let h1 = hash_refresh_token("token-a");
        let h2 = hash_refresh_token("token-b");
        assert_ne!(h1, h2);
    }

    #[test]
    fn ttl_is_within_trd_range() {
        assert!(
            (14..=30).contains(&REFRESH_TOKEN_TTL_DAYS),
            "TTL must be in 14–30 day range per TRD §2.5.1, got {REFRESH_TOKEN_TTL_DAYS}"
        );
    }
}
