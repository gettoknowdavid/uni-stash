use std::sync::Arc;

use crate::core::config::Config;

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
            // aws-sdk-s3 >= 1.14x requires an explicit behavior major version
            // when constructing a client; latest() pins us to current semantics
            // rather than an SDK default that could change under us.
            .behavior_version(aws_sdk_s3::config::BehaviorVersion::latest())
            .region(aws_sdk_s3::config::Region::new("auto"))
            .endpoint_url(&config.r2_endpoint)
            .credentials_provider(credentials)
            .build();
        let inner = Arc::new(aws_sdk_s3::Client::from_conf(conf));
        let bucket = config.r2_bucket.clone();
        Self { inner, bucket }
    }
}
