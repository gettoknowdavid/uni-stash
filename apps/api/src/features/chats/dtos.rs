use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize, validator::Validate)]
pub struct CreateChatRequest {
    pub listing_id: Uuid,
}

#[derive(Debug, Deserialize, validator::Validate)]
pub struct SendMessageRequest {
    #[validate(length(min = 1, max = 5000))]
    pub body: String,
}
