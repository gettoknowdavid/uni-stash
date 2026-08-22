/// One-Time Password utilities for email verification and password reset.
///
/// ## Security model
///
/// - OTPs are 6-digit numeric codes (10^6 = 1M possibilities).
/// - Stored as SHA-256 hashes — plaintext is sent via email and never persisted.
/// - Each OTP has a short TTL (10 minutes) to limit the brute-force window.
/// - Single-use: the `used_at` column prevents replay.
/// - Rate limiting on the auth endpoints (10 req/min per IP + per-email)
///   prevents automated spray attacks.
///
/// ## Why SHA-256 (not Argon2)?
///
/// OTPs are high-entropy random codes (not user-chosen passwords), so the
/// slow KDF used for passwords is unnecessary overhead. SHA-256 is fast
/// and sufficient here — the real defense is the short TTL + rate limiting.
use crate::core::error::AppError;

/// OTP length in digits. 6 digits = 1M possibilities, which is the
/// industry standard (Google, Microsoft, Authy all use 6 digits).
pub const OTP_LENGTH: usize = 6;

/// OTP validity window in minutes. 10 minutes is a good balance:
/// long enough for email delivery delays, short enough to limit exposure.
pub const OTP_TTL_MINUTES: i64 = 10;

/// Generate a random 6-digit OTP code.
///
/// Uses `rand` for cryptographic randomness. The code is zero-padded
/// so it's always exactly 6 characters (e.g., "004217").
pub fn generate_otp() -> String {
    use rand::RngExt;
    let code: u32 = rand::rng().random_range(0..1_000_000u32);
    format!("{:06}", code)
}

/// Hash an OTP code using SHA-256 for storage.
///
/// The plaintext code is sent to the user via email. Only the hash is
/// stored in the database, so a database breach doesn't leak usable OTPs.
pub fn hash_otp(code: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(code.as_bytes());
    hex::encode(hasher.finalize())
}

/// Validate OTP format (must be exactly 6 digits).
pub fn validate_otp_format(code: &str) -> Result<(), AppError> {
    if code.len() != OTP_LENGTH || !code.chars().all(|c| c.is_ascii_digit()) {
        return Err(AppError::BadRequest("invalid OTP format".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_otp_produces_6_digit_string() {
        let otp = generate_otp();
        assert_eq!(otp.len(), OTP_LENGTH);
        assert!(otp.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn generate_otp_pads_leading_zeros() {
        // With 1M possibilities, we can't guarantee a specific value,
        // but we can verify the format is always 6 chars.
        for _ in 0..1000 {
            let otp = generate_otp();
            assert_eq!(otp.len(), 6, "OTP should always be 6 chars: {otp}");
        }
    }

    #[test]
    fn hash_otp_is_deterministic() {
        let h1 = hash_otp("123456");
        let h2 = hash_otp("123456");
        assert_eq!(h1, h2);
    }

    #[test]
    fn hash_otp_differs_for_different_codes() {
        let h1 = hash_otp("123456");
        let h2 = hash_otp("654321");
        assert_ne!(h1, h2);
    }

    #[test]
    fn hash_otp_produces_64_char_hex_string() {
        let h = hash_otp("000000");
        assert_eq!(h.len(), 64, "SHA-256 hex should be 64 chars");
        assert!(h.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn validate_otp_format_accepts_valid_codes() {
        assert!(validate_otp_format("000000").is_ok());
        assert!(validate_otp_format("123456").is_ok());
        assert!(validate_otp_format("999999").is_ok());
    }

    #[test]
    fn validate_otp_format_rejects_too_short() {
        assert!(validate_otp_format("12345").is_err());
    }

    #[test]
    fn validate_otp_format_rejects_too_long() {
        assert!(validate_otp_format("1234567").is_err());
    }

    #[test]
    fn validate_otp_format_rejects_letters() {
        assert!(validate_otp_format("abcdef").is_err());
    }

    #[test]
    fn validate_otp_format_rejects_mixed() {
        assert!(validate_otp_format("12ab56").is_err());
    }
}
