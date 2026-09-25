use actix_web::{HttpResponse, web};
use serde::Serialize;
use uuid::Uuid;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::blocks::repo::BlockedUserResponse;

#[derive(Serialize)]
pub struct BlockedUsersResponse {
    pub blocked_users: Vec<BlockedUserResponse>,
}

/// POST /api/v1/blocks/{user_id} — block a user. Idempotent; self-block is
/// a 400, unknown user a 404.
pub async fn block_user(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let blocked_id = path.into_inner();
    if blocked_id == user.id {
        return Err(AppError::BadRequest("you cannot block yourself".into()));
    }

    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)",
    )
    .bind(blocked_id)
    .fetch_one(&state.db)
    .await?;
    if !exists {
        return Err(AppError::NotFound("user not found".into()));
    }

    state.blocks_repo.block(user.id, blocked_id).await?;

    Ok(
        HttpResponse::Created().json(ApiResponse::<(), ErrorBody>::success(
            (),
            "user blocked successfully",
        )),
    )
}

/// DELETE /api/v1/blocks/{user_id} — unblock. 404 when no block exists.
pub async fn unblock_user(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let blocked_id = path.into_inner();
    let removed = state.blocks_repo.unblock(user.id, blocked_id).await?;
    if !removed {
        return Err(AppError::NotFound("block not found".into()));
    }
    Ok(HttpResponse::NoContent().finish())
}

/// GET /api/v1/blocks/mine — the caller's block list.
pub async fn list_blocked(
    state: web::Data<AppState>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let blocked_users = state.blocks_repo.blocked_users(user.id).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<BlockedUsersResponse, ErrorBody>::success(
            BlockedUsersResponse { blocked_users },
            "ok",
        )),
    )
}
