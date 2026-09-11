use actix_web::{HttpResponse, web};
use validator::Validate;

use crate::core::auth::middleware::AdminSession;
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::categories::dtos::{
    CreateCategoryRequest, CreateCategoryResponse, ListCategoriesResponse, UpdateCategoryRequest,
    UpdateCategoryResponse,
};

pub async fn list_categories(
    state: web::Data<AppState>,
) -> Result<HttpResponse, crate::core::error::AppError> {
    let categories = state.categories_repo.list_categories().await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<ListCategoriesResponse, ErrorBody>::success(
            ListCategoriesResponse { categories },
            "ok",
        )),
    )
}

// ---------------------------------------------------------------------------
// POST /api/v1/categories — admin-only, create a new category
// ---------------------------------------------------------------------------

pub async fn create_category(
    session: AdminSession,
    state: web::Data<AppState>,
    body: ValidatedJson<CreateCategoryRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    if !session.can("categories", "write") {
        return Err(AppError::Forbidden);
    }

    let sort_order = body.sort_order.unwrap_or(0);
    let category = state
        .categories_repo
        .create_category(&body.slug, &body.label, sort_order)
        .await?;

    Ok(
        HttpResponse::Created().json(ApiResponse::<CreateCategoryResponse, ErrorBody>::success(
            CreateCategoryResponse {
                id: category.id,
                slug: category.slug,
                label: category.label,
                message: "category created successfully".to_string(),
            },
            "category created successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// PATCH /api/v1/categories/{id} — admin-only, partial update
// ---------------------------------------------------------------------------

pub async fn update_category(
    session: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<i16>,
    body: ValidatedJson<UpdateCategoryRequest>,
) -> Result<HttpResponse, AppError> {
    let category_id = path.into_inner();
    body.validate()?;

    if !session.can("categories", "write") {
        return Err(AppError::Forbidden);
    }

    // Ensure at least one field is being updated
    if body.slug.is_none() && body.label.is_none() && body.sort_order.is_none() {
        return Err(AppError::BadRequest(
            "at least one of 'slug', 'label' or 'sort_order' must be provided".to_string(),
        ));
    }

    let category = state
        .categories_repo
        .update_category(
            category_id,
            body.slug.as_deref(),
            body.label.as_deref(),
            body.sort_order,
        )
        .await?;

    Ok(
        HttpResponse::Ok().json(ApiResponse::<UpdateCategoryResponse, ErrorBody>::success(
            UpdateCategoryResponse {
                id: category.id,
                slug: category.slug,
                label: category.label,
                message: "category updated successfully".to_string(),
            },
            "category updated successfully",
        )),
    )
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/categories/{id} — admin-only, delete an empty category
// ---------------------------------------------------------------------------

pub async fn delete_category(
    session: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<i16>,
) -> Result<HttpResponse, AppError> {
    let category_id = path.into_inner();

    if !session.can("categories", "write") {
        return Err(AppError::Forbidden);
    }

    // Refuse to delete a category that still has listings — the schema's
    // ON DELETE CASCADE would silently destroy user data.
    let listing_count = state.categories_repo.count_listings(category_id).await?;
    if listing_count > 0 {
        return Err(AppError::Conflict(format!(
            "category still has {listing_count} listing(s); reassign or delete them before deleting the category"
        )));
    }

    state.categories_repo.delete_category(category_id).await?;

    Ok(HttpResponse::NoContent().finish())
}
