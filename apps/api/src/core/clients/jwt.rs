use std::sync::Arc;

use jsonwebtoken::{DecodingKey, EncodingKey};

use crate::core::error::AppError;

#[derive(Clone, Debug)]
pub struct JwtKeys {
    pub encoding: Arc<EncodingKey>,
    pub decoding: Arc<DecodingKey>,
}
impl JwtKeys {
    pub fn from_pem(private_pem: &str, public_pem: &str) -> anyhow::Result<Self, AppError> {
        let encoding = EncodingKey::from_rsa_pem(private_pem.as_bytes())
            .map_err(|e| AppError::Internal(anyhow::anyhow!("invalid JWT private key PEM: {e}")))?;
        let decoding = DecodingKey::from_rsa_pem(public_pem.as_bytes())
            .map_err(|e| AppError::Internal(anyhow::anyhow!("invalid JWT public key PEM: {e}")))?;
        Ok(Self {
            encoding: Arc::new(encoding),
            decoding: Arc::new(decoding),
        })
    }
}
