use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;

use crate::core::{
    auth::middleware::AuthUser,
    cursor::{Cursor, decode_cursor, encode_cursor},
    error::AppError,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::saved_items::repo::{SavedItemResponse, SavedItemsListResponse};

#[derive(Deserialize)]
pub struct SavedItemsQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

fn paginate(rows: Vec<SavedItemResponse>, limit: i64) -> (Vec<SavedItemResponse>, Option<String>) {
    let has_more = rows.len() as i64 > limit;
    let mut rows = rows;
    if has_more {
        rows.truncate(limit as usize);
    }
    let next_cursor = has_more.then(|| {
        let last = rows.last().expect("has_more implies non-empty");
        encode_cursor(&Cursor {
            created_at: last.saved_at,
            id: last.listing_id,
        })
    });
    (rows, next_cursor)
}

// GET /api/v1/saved-items — the signed-in user's saved listings, newest first.
pub async fn list_saved(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<SavedItemsQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(50).clamp(1, 100);
    let cursor = match &query.cursor {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let rows = state
        .saved_items_repo
        .list_for_user(
            user.id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let (items, next_cursor) = paginate(rows, limit);
    Ok(
        HttpResponse::Ok().json(ApiResponse::<SavedItemsListResponse, ErrorBody>::success(
            SavedItemsListResponse { items, next_cursor },
            "ok",
        )),
    )
}

// POST /api/v1/saved-items/{id} — save a listing. Idempotent.
pub async fn save_item(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let listing_id = path.into_inner();
    state.saved_items_repo.save(user.id, listing_id).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "listing saved successfully",
        )),
    )
}

// DELETE /api/v1/saved-items/{id} — unsave a listing. Idempotent.
pub async fn unsave_item(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let listing_id = path.into_inner();
    state.saved_items_repo.unsave(user.id, listing_id).await?;
    Ok(HttpResponse::NoContent().finish())
}

// GET /api/v1/saved-items/{id}/status — whether the signed-in user saved it.
// Used by the detail page to render the filled bookmark state.
pub async fn item_status(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let listing_id = path.into_inner();
    let saved = state.saved_items_repo.is_saved(user.id, listing_id).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<SavedItemStatusResponse, ErrorBody>::success(
            SavedItemStatusResponse { saved },
            "ok",
        )),
    )
}

#[derive(serde::Serialize)]
pub struct SavedItemStatusResponse {
    pub saved: bool,
}
