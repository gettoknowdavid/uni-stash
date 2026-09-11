use actix_web::{HttpResponse, web};

use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::categories::dtos::ListCategoriesResponse;

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
