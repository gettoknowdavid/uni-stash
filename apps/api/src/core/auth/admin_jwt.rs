use anyhow::anyhow;
use jsonwebtoken::{decode, errors::ErrorKind};
use uuid::Uuid;

use crate::core::{clients::JwtKeys, error::AppError};

/// Access token TTL in minutes — same as student access tokens.
const ADMIN_ACCESS_TOKEN_TTL_MINUTES: i64 = 15;

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
pub struct AdminAccessClaims {
    pub sub: Uuid,
    pub exp: i64,
    pub iat: i64,
    /// Always "admin_access" — a student access token (purpose: "access")
    /// must never validate against `verify_admin_access_token` and vice versa.
    pub purpose: String,
    /// Informational only, never trusted for authz decisions.
    pub level: String,
}

/// Signs an admin access token using the provided JWT keys.
pub fn sign_admin_access_token(
    keys: &JwtKeys,
    admin_id: Uuid,
    level: &str,
) -> Result<String, AppError> {
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    let claims = AdminAccessClaims {
        sub: admin_id,
        iat: now,
        exp: now + (ADMIN_ACCESS_TOKEN_TTL_MINUTES * 60),
        purpose: "admin_access".to_string(),
        level: level.to_string(),
    };
    let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
    let token = jsonwebtoken::encode(&header, &claims, &keys.encoding)
        .map_err(|e| AppError::Internal(anyhow!("failed to sign admin token: {e}")))?;
    Ok(token)
}

/// Verifies an admin access token and returns the claims.
pub fn verify_admin_access_token(
    keys: &JwtKeys,
    token: &str,
) -> Result<AdminAccessClaims, AppError> {
    let mut validation = jsonwebtoken::Validation::new(jsonwebtoken::Algorithm::RS256);
    validation.set_required_spec_claims(&["exp", "sub"]);

    let token_data = match decode::<AdminAccessClaims>(token, &keys.decoding, &validation) {
        Err(e) if e.kind() == &ErrorKind::ExpiredSignature => {
            return Err(AppError::TokenExpired);
        }
        Err(_) => return Err(AppError::Unauthorized("invalid token".to_string())),
        Ok(token_data) => token_data,
    };
    let claims = token_data.claims;

    if claims.purpose != "admin_access" {
        return Err(AppError::Unauthorized("invalid token purpose".to_string()));
    }

    Ok(claims)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{str::FromStr, sync::Arc};

    use jsonwebtoken::{DecodingKey, EncodingKey};

    const ADMIN_ID_STR: &str = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    const TEST_PRIVATE_PEM: &str = include_str!("../../../tests/fixtures/test_rsa_private.pem");
    const TEST_PUBLIC_PEM: &str = include_str!("../../../tests/fixtures/test_rsa_public.pem");

    fn test_keys() -> JwtKeys {
        JwtKeys {
            encoding: Arc::new(EncodingKey::from_rsa_pem(TEST_PRIVATE_PEM.as_bytes()).unwrap()),
            decoding: Arc::new(DecodingKey::from_rsa_pem(TEST_PUBLIC_PEM.as_bytes()).unwrap()),
        }
    }

    fn encode_claims(keys: &JwtKeys, claims: &AdminAccessClaims) -> String {
        jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256),
            claims,
            &keys.encoding,
        )
        .expect("encode test token")
    }

    #[test]
    fn test_admin_token_round_trips() {
        let keys = test_keys();
        let admin_id = Uuid::from_str(ADMIN_ID_STR).unwrap();
        let token = sign_admin_access_token(&keys, admin_id, "super").unwrap();
        let claims = verify_admin_access_token(&keys, &token).unwrap();
        assert_eq!(claims.sub, admin_id);
        assert_eq!(claims.purpose, "admin_access");
        assert_eq!(claims.level, "super");
    }

    #[test]
    fn test_expired_admin_token_is_rejected() {
        let keys = test_keys();
        let now = time::OffsetDateTime::now_utc().unix_timestamp();
        let admin_id = Uuid::from_str(ADMIN_ID_STR).unwrap();
        let claims = AdminAccessClaims {
            sub: admin_id,
            iat: now - 7200,
            exp: now - 3600,
            purpose: "admin_access".to_string(),
            level: "super".to_string(),
        };
        let token = encode_claims(&keys, &claims);
        let result = verify_admin_access_token(&keys, &token);
        assert!(result.is_err());
        std::assert_matches!(result.err(), Some(AppError::TokenExpired));
    }

    #[test]
    fn test_student_token_rejected_by_admin_verifier() {
        let keys = test_keys();
        let now = time::OffsetDateTime::now_utc().unix_timestamp();
        let admin_id = Uuid::from_str(ADMIN_ID_STR).unwrap();
        let claims = AdminAccessClaims {
            sub: admin_id,
            iat: now,
            exp: now + 900,
            purpose: "access".to_string(), // student purpose
            level: "super".to_string(),
        };
        let token = encode_claims(&keys, &claims);
        let result = verify_admin_access_token(&keys, &token);
        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_purpose_is_rejected() {
        let keys = test_keys();
        let now = time::OffsetDateTime::now_utc().unix_timestamp();
        let admin_id = Uuid::from_str(ADMIN_ID_STR).unwrap();
        let claims = AdminAccessClaims {
            sub: admin_id,
            iat: now,
            exp: now + 900,
            purpose: "email_verify".to_string(),
            level: "super".to_string(),
        };
        let token = encode_claims(&keys, &claims);
        let result = verify_admin_access_token(&keys, &token);
        assert!(result.is_err());
    }

    #[test]
    fn test_tampered_signature_is_rejected() {
        let keys = test_keys();
        let admin_id = Uuid::from_str(ADMIN_ID_STR).unwrap();
        let token = sign_admin_access_token(&keys, admin_id, "super").unwrap();
        let tampered = token[..token.len() - 5].to_string() + "AAAAA";
        let result = verify_admin_access_token(&keys, &tampered);
        assert!(result.is_err());
    }
}
