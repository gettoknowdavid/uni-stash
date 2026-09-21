use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::core::{
    auth::middleware::AuthUser,
    cursor::{Cursor, decode_cursor, encode_cursor},
    error::AppError,
    json::ValidatedJson,
    realtime::{RealtimeEvent, private_channel},
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::chats::dtos::{CreateChatRequest, SendMessageRequest};
use crate::features::chats::models::{ChatThreadResponse, MessageResponse};

#[derive(serde::Serialize)]
struct ChatCreatedResponse {
    chat_id: Uuid,
}

#[derive(serde::Serialize)]
struct ThreadListResponse {
    chats: Vec<ChatThreadResponse>,
}

#[derive(serde::Serialize)]
struct MessageListResponse {
    messages: Vec<MessageResponse>,
    next_cursor: Option<String>,
}

#[derive(Deserialize)]
pub struct MessagesQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

/// Verify the requester is a participant of the chat; 404 if the chat
/// doesn't exist, 403 if it isn't theirs.
async fn ensure_participant(
    state: &AppState,
    chat_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    match state.chats_repo.participants(chat_id).await? {
        None => Err(AppError::NotFound("chat not found".into())),
        Some((buyer_id, seller_id)) => {
            if user_id == buyer_id || user_id == seller_id {
                Ok(())
            } else {
                Err(AppError::Forbidden)
            }
        }
    }
}

pub async fn create_chat(
    state: web::Data<AppState>,
    user: AuthUser,
    body: ValidatedJson<CreateChatRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    if !user.email_verified {
        return Err(AppError::EmailNotVerified);
    }

    // The listing must exist (the repo INSERT...SELECT fails otherwise).
    // Chatting with yourself on your own listing is pointless but harmless —
    // rejected for clarity.
    let listing = state
        .listings_repo
        .find_detail_by_id(body.listing_id)
        .await?
        .ok_or_else(|| AppError::NotFound("listing not found".into()))?;
    if listing.seller.id == user.id {
        return Err(AppError::BadRequest(
            "cannot start a chat on your own listing".into(),
        ));
    }

    let chat_id = state
        .chats_repo
        .create_for_listing(body.listing_id, user.id)
        .await?;

    Ok(
        HttpResponse::Created().json(ApiResponse::<ChatCreatedResponse, ErrorBody>::success(
            ChatCreatedResponse { chat_id },
            "chat ready",
        )),
    )
}

// ---------------------------------------------------------------------------
// GET /api/v1/chats — the requester's thread list
// ---------------------------------------------------------------------------

pub async fn list_chats(
    state: web::Data<AppState>,
    user: AuthUser,
    query: web::Query<LimitQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 50);
    let chats = state.chats_repo.threads_for_user(user.id, limit).await?;
    Ok(
        HttpResponse::Ok().json(ApiResponse::<ThreadListResponse, ErrorBody>::success(
            ThreadListResponse { chats },
            "ok",
        )),
    )
}

#[derive(Deserialize)]
pub struct LimitQuery {
    pub limit: Option<i64>,
}

// ---------------------------------------------------------------------------
// GET /api/v1/chats/{id}/messages — history (newest first, cursor-paginated)
// ---------------------------------------------------------------------------

pub async fn list_messages(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    user: AuthUser,
    query: web::Query<MessagesQuery>,
) -> Result<HttpResponse, AppError> {
    let chat_id = path.into_inner();
    ensure_participant(&state, chat_id, user.id).await?;

    let limit = query.limit.unwrap_or(30).clamp(1, 100);
    let cursor = match &query.cursor {
        Some(raw) => Some(decode_cursor(raw)?),
        None => None,
    };

    let mut rows = state
        .chats_repo
        .messages(
            chat_id,
            cursor.as_ref().map(|c| c.created_at),
            cursor.as_ref().map(|c| c.id),
            limit,
        )
        .await?;

    let has_more = rows.len() as i64 > limit;
    if has_more {
        rows.truncate(limit as usize);
    }
    let next_cursor = has_more.then(|| {
        let last = rows.last().expect("has_more implies non-empty");
        encode_cursor(&Cursor {
            created_at: last.created_at,
            id: last.id,
        })
    });

    Ok(
        HttpResponse::Ok().json(ApiResponse::<MessageListResponse, ErrorBody>::success(
            MessageListResponse {
                messages: rows,
                next_cursor,
            },
            "ok",
        )),
    )
}

// ---------------------------------------------------------------------------
// POST /api/v1/chats/{id}/messages — send (REST fallback / source of truth)
// ---------------------------------------------------------------------------

pub async fn send_message(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    user: AuthUser,
    body: ValidatedJson<SendMessageRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;
    let chat_id = path.into_inner();
    ensure_participant(&state, chat_id, user.id).await?;

    let message = state
        .chats_repo
        .send_message(chat_id, user.id, body.body.trim())
        .await?;

    // Best-effort realtime push — never fails the request; the DB row is
    // the source of truth and clients catch up on reconnect.
    if let Err(err) = state
        .realtime
        .0
        .publish(
            &private_channel(&chat_id.to_string()),
            &RealtimeEvent::MessageNew { chat_id },
        )
        .await
    {
        tracing::warn!(
            chat_id = %chat_id,
            error = %err,
            "realtime publish failed (message still persisted)"
        );
    }

    // Best-effort push notification to the other participant.
    if let Ok(Some((buyer_id, seller_id))) = state.chats_repo.participants(chat_id).await {
        let recipient = if user.id == buyer_id {
            seller_id
        } else {
            buyer_id
        };
        let sender_name = &user.display_name;
        let preview = if body.body.len() > 80 {
            &body.body[..80]
        } else {
            &body.body
        };
        if let Err(err) = state
            .push_sender
            .0
            .send_to_user(
                recipient,
                sender_name,
                preview,
                Some(&[("chat_id", &chat_id.to_string())]),
            )
            .await
        {
            tracing::warn!(chat_id = %chat_id, error = %err, "push notification failed");
        }
    }

    Ok(
        HttpResponse::Created().json(ApiResponse::<MessageResponse, ErrorBody>::success(
            message,
            "message sent",
        )),
    )
}

// ---------------------------------------------------------------------------
// POST /api/v1/chats/{id}/read — mark the counterpart's messages read
// ---------------------------------------------------------------------------

pub async fn mark_read(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
    user: AuthUser,
) -> Result<HttpResponse, AppError> {
    let chat_id = path.into_inner();
    ensure_participant(&state, chat_id, user.id).await?;

    if let Some(last_read_id) = state.chats_repo.mark_read(chat_id, user.id).await?
        && let Err(err) = state
            .realtime
            .0
            .publish(
                &private_channel(&chat_id.to_string()),
                &RealtimeEvent::MessageRead {
                    chat_id,
                    last_read_message_id: last_read_id,
                },
            )
            .await
    {
        tracing::warn!(chat_id = %chat_id, error = %err, "realtime read-receipt publish failed");
    }

    Ok(HttpResponse::Ok().json(ApiResponse::<(), ErrorBody>::success((), "marked read")))
}

// ---------------------------------------------------------------------------
// POST /api/v1/realtime/auth — private-channel subscription auth
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct RealtimeAuthRequest {
    pub socket_id: String,
    pub channel_name: String,
}

pub async fn realtime_auth(
    state: web::Data<AppState>,
    user: AuthUser,
    body: web::Json<RealtimeAuthRequest>,
) -> Result<HttpResponse, AppError> {
    // Only private-chat-{uuid} channels are signable, and only by
    // participants of that chat.
    let chat_id = body
        .channel_name
        .strip_prefix("private-chat-")
        .and_then(|raw| Uuid::parse_str(raw).ok())
        .ok_or_else(|| AppError::BadRequest("invalid channel".into()))?;
    ensure_participant(&state, chat_id, user.id).await?;

    let socket_id = body.socket_id.trim();
    if socket_id.is_empty() || socket_id.contains(':') {
        return Err(AppError::BadRequest("invalid socket_id".into()));
    }

    let auth = state
        .realtime
        .0
        .authenticate_channel(socket_id, &body.channel_name)
        .ok_or_else(|| AppError::BadRequest("realtime channel auth is not configured".into()))?;

    Ok(HttpResponse::Ok().body(auth))
}
