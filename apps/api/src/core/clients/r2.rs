use std::sync::Arc;
use std::time::Duration;

use aws_sdk_s3::presigning::PresigningConfig;

use crate::core::config::Config;
use crate::core::error::AppError;

/// Default presigned URL lifetime — long enough for a mobile client to upload,
/// short enough to limit abuse if a URL leaks.
const PRESIGN_EXPIRY: Duration = Duration::from_secs(5 * 60); // 5 minutes

/// Maximum object size accepted during the HEAD verification in CM-6.2.
/// 10 MiB — generous for campus listing photos, tight enough to prevent abuse
/// on the free tier.
const MAX_OBJECT_SIZE: u64 = 10 * 1024 * 1024;

#[derive(Clone, Debug)]
pub struct R2Client {
    pub inner: Arc<aws_sdk_s3::Client>,
    pub bucket: String,
}

impl R2Client {
    pub fn from_config(config: &Config) -> Self {
        let credentials = aws_sdk_s3::config::Credentials::new(
            &config.r2_access_key_id,
            &config.r2_secret_access_key,
            None,
            None,
            "r2",
        );
        let conf = aws_sdk_s3::config::Builder::new()
            .behavior_version(aws_sdk_s3::config::BehaviorVersion::latest())
            .region(aws_sdk_s3::config::Region::new("auto"))
            .endpoint_url(&config.r2_endpoint)
            .credentials_provider(credentials)
            .build();
        let inner = Arc::new(aws_sdk_s3::Client::from_conf(conf));
        let bucket = config.r2_bucket.clone();
        Self { inner, bucket }
    }

    // ------------------------------------------------------------------
    // CM-6.1 — Presigned PUT URL for direct client upload
    // ------------------------------------------------------------------

    /// Generate a time-limited presigned PUT URL so the mobile client can
    /// upload an image directly to Backblaze B2 without proxying through
    /// the server.
    pub async fn presign_put(&self, key: &str, content_type: &str) -> Result<String, AppError> {
        let presigned = self
            .inner
            .put_object()
            .bucket(&self.bucket)
            .key(key)
            .content_type(content_type)
            .presigned(
                PresigningConfig::expires_in(PRESIGN_EXPIRY)
                    .map_err(|e| anyhow::anyhow!("presigning config: {e}"))?,
            )
            .await
            .map_err(|e| anyhow::anyhow!("failed to generate presigned URL: {e}"))?;

        Ok(presigned.uri().to_string())
    }

    // ------------------------------------------------------------------
    // CM-6.2 — HEAD check to verify object landed in B2
    // ------------------------------------------------------------------

    /// Verify that an object exists in the bucket and is within size limits.
    /// Returns the object size in bytes, or an error if missing / oversized.
    pub async fn head_object_size(&self, key: &str) -> Result<u64, AppError> {
        let resp = self
            .inner
            .head_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
            .map_err(|e| {
                let msg = e.to_string();
                if msg.contains("NoSuchKey") || msg.contains("404") {
                    AppError::BadRequest("uploaded file not found in storage".into())
                } else {
                    anyhow::anyhow!("failed to verify uploaded file: {e}").into()
                }
            })?;

        let size = resp.content_length().unwrap_or(0) as u64;
        if size > MAX_OBJECT_SIZE {
            return Err(AppError::BadRequest(format!(
                "file too large: {size} bytes (max {MAX_OBJECT_SIZE})"
            )));
        }
        if size == 0 {
            return Err(AppError::BadRequest("uploaded file is empty".into()));
        }

        Ok(size)
    }

    // ------------------------------------------------------------------
    // CM-6.3 — Delete object from B2
    // ------------------------------------------------------------------

    /// Delete an object from the bucket. Logs failures but does not propagate
    /// errors — the DB row is the source of truth, and B2 cleanup is best-effort.
    pub async fn delete_object(&self, key: &str) {
        if let Err(e) = self
            .inner
            .delete_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
        {
            tracing::warn!(key = key, error = %e, "failed to delete object from B2");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn max_object_size_is_sane() {
        // 10 MiB — sanity check that the constant wasn't accidentally changed
        assert_eq!(MAX_OBJECT_SIZE, 10 * 1024 * 1024);
    }

    #[test]
    fn presign_expiry_is_reasonable() {
        // 5 minutes — enough for upload, short enough to limit abuse
        assert_eq!(PRESIGN_EXPIRY.as_secs(), 300);
    }
}
