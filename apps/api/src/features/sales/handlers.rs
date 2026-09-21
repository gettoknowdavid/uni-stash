use actix_web::{HttpResponse, web};
use base64::Engine;
use serde::Deserialize;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::sales::repo::SaleResponse;

/// Opaque cursor: `created_at_unix_nanos:sale_id` (mirrors the listings
/// cursor format so mobile can treat them identically).
#[derive(Deserialize)]
pub struct SalesQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

struct Cursor {
    created_at: OffsetDateTime,
    id: Uuid,
}

fn decode_cursor(raw: &str) -> Result<Cursor, AppError> {
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(raw)
        .map_err(|_| AppError::BadRequest("invalid cursor".into()))?;
    let s =
        String::from_utf8(decoded).map_err(|_| AppError::BadRequest("invalid cursor".into()))?;
    let mut parts = s.split(':');
    let nanos = parts
        .next()
        .and_then(|p| p.parse::<i128>().ok())
        .ok_or_else(|| AppError::BadRequest("invalid cursor".into()))?;
    let id = parts
        .next()
        .and_then(|p| Uuid::parse_str(p).ok())
        .ok_or_else(|| AppError::BadRequest("invalid cursor".into()))?;
    Ok(Cursor {
        created_at: OffsetDateTime::from_unix_timestamp_nanos(nanos)
            .map_err(|_| AppError::BadRequest("invalid cursor".into()))?,
        id,
    })
}

fn encode_cursor(created_at: OffsetDateTime, id: Uuid) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(format!(
        "{}:{}",
        created_at.unix_timestamp_nanos(),
        id
    ))
}

fn paginate(rows: Vec<SaleResponse>, limit: i64) -> (Vec<SaleResponse>, Option<String>) {
    let has_more = rows.len() as i64 > limit;
    let mut rows = rows;
    if has_more {
        rows.truncate(limit as usize);
    }
    let next_cursor = has_more.then(|| {
        let last = rows.last().expect("has_more implies non-empty");
        encode_cursor(last.created_at, last.id)
    });
    (rows, next_cursor)
}

// GET /api/v1/sales/purchases — items this user bought
pub async fn my_purchases(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<SalesQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let cursor = match &query.cursor {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let rows = state
        .sales_repo
        .purchases_for_user(
            user.id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let (sales, next_cursor) = paginate(rows, limit);
    Ok(
        HttpResponse::Ok().json(ApiResponse::<SalesListResponse, ErrorBody>::success(
            SalesListResponse { sales, next_cursor },
            "ok",
        )),
    )
}

// GET /api/v1/sales/mine — items this user sold
pub async fn my_sales(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<SalesQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let cursor = match &query.cursor {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let rows = state
        .sales_repo
        .sales_for_user(
            user.id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let (sales, next_cursor) = paginate(rows, limit);
    Ok(
        HttpResponse::Ok().json(ApiResponse::<SalesListResponse, ErrorBody>::success(
            SalesListResponse { sales, next_cursor },
            "ok",
        )),
    )
}

#[derive(serde::Serialize)]
pub struct SalesListResponse {
    pub sales: Vec<SaleResponse>,
    pub next_cursor: Option<String>,
}
