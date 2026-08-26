use std::sync::OnceLock;

use anyhow::anyhow;
use argon2::{Algorithm::Argon2id, PasswordHasher, PasswordVerifier, Version};

use crate::core::error::AppError;

// A fixed, precomputed Argon2id hash of a random string, generated once at
// compile time or lazily via OnceLock — NEVER matches any real password.
// Used to keep the timing profile identical between "user not found" and
// "user found, wrong password" paths.
pub static DUMMY_HASH: OnceLock<String> = OnceLock::new();

/// Free-tier memory budget note: 19 MiB / 2 iterations / 1 lane is the OWASP
/// FLOOR for Argon2id, not a target — chosen because the deploy target
/// (Render free tier) is memory-constrained. Bump these up if/when more
/// headroom becomes available; this is the one place that value lives.
///
/// `Params::new` is fallible (invalid combinations of cost params are
/// rejected at construction), so it can't be a `const`/`static` — build it
/// fresh via this helper instead. The `.expect` here is safe: these are
/// fixed, known-valid literals we control, not runtime input.
fn argon2_params() -> argon2::Params {
    argon2::Params::new(19_456, 2, 1, None).expect("hardcoded Argon2 params are valid")
}

/// Hashes a password using Argon2id with the default parameters.
///
/// Returns a PHC string (e.g. `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`).
pub fn hash_password(raw: &str) -> Result<String, AppError> {
    let salt = argon2::password_hash::SaltString::generate(argon2::password_hash::rand_core::OsRng);
    let argon2 = argon2::Argon2::new(Argon2id, Version::V0x13, argon2_params());
    argon2
        .hash_password(raw.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|e| AppError::Internal(anyhow!("password hashing failed: {e}")))
}

/// Verifies a password against a stored hash.
///
/// Returns `true` if the password matches the stored hash, `false` otherwise.
pub fn verify_password(raw: &str, stored_hash: &str) -> Result<bool, AppError> {
    let parsed_hash = argon2::PasswordHash::new(stored_hash);
    let hash = parsed_hash.map_err(|_| AppError::Internal(anyhow!("stored hash is malformed")))?;
    let argon2 = argon2::Argon2::default();
    let verify_result = argon2.verify_password(raw.as_bytes(), &hash);
    match verify_result {
        Ok(_) => Ok(true),
        Err(argon2::password_hash::Error::Password) => Ok(false),
        Err(e) => Err(AppError::Internal(anyhow!(e))),
    }
}

/// Returns a precomputed dummy hash that matches no real password.
pub fn dummy_hash() -> &'static str {
    DUMMY_HASH.get_or_init(|| hash_password("dummy-password-never-matches-anything").unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_correct_password_verifies_true() {
        let hash = hash_password("correct horse battery staple twice").unwrap();
        assert!(verify_password("correct horse battery staple twice", &hash).unwrap());
    }

    #[test]
    fn test_incorrect_password_verifies_false() {
        let hash = hash_password("correct horse battery staple twice").unwrap();
        assert!(!verify_password("correct horse battery staple", &hash).unwrap());
    }

    #[test]
    fn test_malformed_hash_returns_error_not_panic() {
        let result = verify_password("some string", "some password hash");
        assert!(result.is_err())
    }
}
