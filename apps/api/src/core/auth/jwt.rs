use anyhow::anyhow;
use jsonwebtoken::{decode, errors::ErrorKind};
use uuid::Uuid;

use crate::core::{error::AppError, state::JwtKeys};

/// Access token TTL in minutes.
const ACCESS_TOKEN_TTL_MINUTES: i64 = 15;

/// Access token claims.
#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
pub struct AccessClaims {
    pub sub: Uuid,
    pub exp: i64,
    pub iat: i64,
    pub purpose: String,
    pub email: String,
    pub display_name: String,
    pub email_verified: bool,
}

/// Signs an access token using the provided JWT keys and claims.
///
/// Returns the signed token as a string, or an `AppError` if signing fails.
pub fn sign_access_token(
    keys: &JwtKeys,
    user_id: Uuid,
    email: String,
    display_name: String,
    email_verified: bool,
) -> Result<String, AppError> {
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    let claims = AccessClaims {
        sub: user_id,
        iat: now,
        exp: now + (ACCESS_TOKEN_TTL_MINUTES * 60),
        purpose: "access".to_string(),
        email: email,
        display_name: display_name,
        email_verified: email_verified,
    };
    let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
    let token = jsonwebtoken::encode(&header, &claims, &keys.encoding)
        .map_err(|e| AppError::Internal(anyhow!("failed to sign token: {e}")))?;
    Ok(token)
}

/// Verifies the access token and returns the claims, or an `AppError` if verification fails.
///
/// # Returns
///
/// - `Ok(claims)`: The claims are valid and the token is not expired.
/// - `Err(AppError::Unauthorized)`: The token is expired or invalid.
pub fn verify_access_token(keys: &JwtKeys, token: &str) -> Result<AccessClaims, AppError> {
    let mut validation = jsonwebtoken::Validation::new(jsonwebtoken::Algorithm::RS256);
    validation.set_required_spec_claims(&["exp", "sub"]);

    let token_data = match decode::<AccessClaims>(token, &keys.decoding, &validation) {
        Err(e) if e.kind() == &ErrorKind::ExpiredSignature => {
            return Err(AppError::TokenExpired);
        }
        Err(_) => return Err(AppError::Unauthorized("invalid token".to_string())),
        Ok(token_data) => token_data,
    };
    let claims = token_data.claims;

    if claims.purpose != "access" {
        return Err(AppError::Unauthorized("invalid token purpose".to_string()));
    }

    Ok(claims)
}

#[cfg(test)]
mod tests {
    use std::{str::FromStr, sync::Arc};

    use jsonwebtoken::{DecodingKey, EncodingKey};

    use super::*;

    const USER_ID_STR: &str = "dad19d3d-f97c-4d9e-8ce4-30565eeb8a07";
    const TEST_PRIVATE_PEM: &str = include_str!("../../../tests/fixtures/test_rsa_private.pem");
    const TEST_PUBLIC_PEM: &str = include_str!("../../../tests/fixtures/test_rsa_public.pem");

    fn test_keys() -> JwtKeys {
        JwtKeys {
            encoding: Arc::new(EncodingKey::from_rsa_pem(TEST_PRIVATE_PEM.as_bytes()).unwrap()),
            decoding: Arc::new(DecodingKey::from_rsa_pem(TEST_PUBLIC_PEM.as_bytes()).unwrap()),
        }
    }

    fn sign_with_custom_claims(keys: &JwtKeys, claims: AccessClaims) -> Result<String, AppError> {
        let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
        let token = jsonwebtoken::encode(&header, &claims, &keys.encoding)
            .map_err(|e| AppError::Internal(anyhow!("failed to sign token: {e}")))?;
        Ok(token)
    }

    #[test]
    fn test_signed_token_round_trips() {
        let keys = test_keys();
        let user_id = Uuid::from_str(USER_ID_STR).unwrap();
        let token = sign_access_token(
            &keys,
            user_id,
            "some@example.com".to_string(),
            "Some User".to_string(),
            true,
        )
        .unwrap();
        let claims = verify_access_token(&keys, &token).unwrap();
        assert_eq!(claims.sub, user_id);
        assert_eq!(claims.purpose, "access");
        assert_eq!(claims.email_verified, true);
    }

    #[test]
    fn test_expired_token_is_rejected() {
        let keys = test_keys();
        let now = time::OffsetDateTime::now_utc().unix_timestamp();
        let user_id = Uuid::from_str(USER_ID_STR).unwrap();
        let claims = AccessClaims {
            sub: user_id,
            iat: now,
            exp: now - 3600,
            purpose: "access".to_string(),
            email: "some@example.com".to_string(),
            display_name: "Some User".to_string(),
            email_verified: true,
        };
        let expired_token = sign_with_custom_claims(&keys, claims).unwrap();
        let expired_result = verify_access_token(&keys, &expired_token);
        assert!(expired_result.is_err());
        std::assert_matches!(expired_result.err(), Some(AppError::TokenExpired));
    }

    #[test]
    fn test_wrong_purpose_is_rejected() {
        let keys = test_keys();
        let now = time::OffsetDateTime::now_utc().unix_timestamp();
        let user_id = Uuid::from_str(USER_ID_STR).unwrap();
        let claims = AccessClaims {
            sub: user_id,
            iat: now,
            exp: now + (ACCESS_TOKEN_TTL_MINUTES * 60),
            purpose: "something-else".to_string(),
            email: "some@example.com".to_string(),
            display_name: "Some User".to_string(),
            email_verified: true,
        };
        let invalid_token = sign_with_custom_claims(&keys, claims).unwrap();
        let invalid_result = verify_access_token(&keys, &invalid_token);
        assert!(invalid_result.is_err());
    }

    #[test]
    fn test_tampered_signature_is_rejected() {
        let keys = test_keys();
        let user_id = Uuid::from_str(USER_ID_STR).unwrap();
        let token = sign_access_token(
            &keys,
            user_id,
            "some@example.com".to_string(),
            "Some User".to_string(),
            true,
        )
        .unwrap();
        let tampered = token[..token.len() - 5].to_string() + "AAAAA";
        let tampered_result = verify_access_token(&keys, &tampered);
        assert!(tampered_result.is_err());
    }
}
