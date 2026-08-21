use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::{
    core::{auth::middleware::AuthUser, error::AppError, json, state::AppState},
    features::listings::dtos::{CreateListingRequest, InsertListingInput, ListingResponse},
};

pub async fn create_listing(
    state: web::Data<AppState>,
    body: json::ValidatedJson<CreateListingRequest>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    if !user.email_verified {
        return Err(AppError::EmailNotVerified);
    }

    body.validate()?;

    let description = body.description.clone().unwrap_or_default();
    let input = InsertListingInput {
        seller_id: user.id,
        category_id: body.category_id,
        title: &body.title,
        description: &description,
        price: body.price,
        condition: body.condition.clone(),
    };
    let listing = state.listings_repo.insert_listing(&input).await?;
    Ok(HttpResponse::Created().json(ListingResponse::from(listing)))
}
