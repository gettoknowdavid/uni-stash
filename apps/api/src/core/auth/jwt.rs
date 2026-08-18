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
    pub email_verified: bool,
}

/// Signs an access token using the provided JWT keys and claims.
///
/// Returns the signed token as a string, or an `AppError` if signing fails.
pub fn sign_access(
    keys: &JwtKeys,
    user_id: Uuid,
    email_verified: bool,
) -> Result<String, AppError> {
    let now = time::OffsetDateTime::now_utc().unix_timestamp();
    let claims = AccessClaims {
        sub: user_id,
        iat: now,
        exp: now + (ACCESS_TOKEN_TTL_MINUTES * 60),
        purpose: "access".to_string(),
        email_verified: email_verified,
    };
    let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
    let token = jsonwebtoken::encode(&header, &claims, &keys.encoding)
        .map_err(|e| AppError::Internal(anyhow!("failued to sign token: {e}")))?;
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
