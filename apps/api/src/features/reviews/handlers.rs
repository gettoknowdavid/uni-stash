use actix_web::{HttpResponse, web};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::core::{
    auth::middleware::AuthUser,
    error::AppError,
    json::ValidatedJson,
    response::{ApiResponse, ErrorBody},
    state::AppState,
};
use crate::features::reviews::repo::{RatingSummary, ReviewResponse};

#[derive(Debug, Deserialize, Validate)]
pub struct CreateReviewRequest {
    #[validate(range(min = 1, max = 5))]
    pub rating: i16,

    #[validate(length(max = 1000))]
    pub comment: Option<String>,
}

#[derive(serde::Serialize)]
pub struct UserReviewsResponse {
    pub reviews: Vec<ReviewResponse>,
    pub average_rating: Option<f64>,
    pub review_count: i64,
}

/// POST /api/v1/reviews/{sale_id} — rate the counterpart of a completed
/// sale. The caller must be the buyer or the seller; the reviewee is
/// always the other party. One review per author per sale.
pub async fn create_review(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
    body: ValidatedJson<CreateReviewRequest>,
) -> Result<HttpResponse, AppError> {
    let sale_id = path.into_inner();

    // 404 when the sale doesn't exist; Forbidden when the caller wasn't
    // part of it (counterpart lookup returns None for non-participants —
    // careful: a walk-up sale with a NULL buyer means the seller can't
    // review anyone, handled by the NULL check below).
    let reviewee = state
        .reviews_repo
        .sale_counterpart(sale_id, user.id)
        .await?
        .ok_or(AppError::Forbidden)?;

    if state.reviews_repo.find_for_sale(sale_id, user.id).await?.is_some() {
        return Err(AppError::Conflict(
            "you have already reviewed this sale".into(),
        ));
    }

    let review = state
        .reviews_repo
        .create(sale_id, user.id, reviewee, body.rating, body.comment.clone())
        .await?;

    // Best-effort inbox notification so the reviewee knows.
    if let Err(err) = state
        .notifications_repo
        .insert_notification(
            reviewee,
            "review.received",
            "New review",
            &format!(
                "{} left you a {}-star review on '{}'",
                review.author_name, review.rating, review.listing_title
            ),
            Some(serde_json::json!({ "listing_id": review.listing_title })),
        )
        .await
    {
        tracing::warn!(error = %err, "review inbox notification failed");
    }

    Ok(
        HttpResponse::Created().json(ApiResponse::<ReviewResponse, ErrorBody>::success(
            review,
            "review submitted",
        )),
    )
}

/// GET /api/v1/reviews/users/{user_id} — a user's rating wall + summary.
pub async fn user_reviews(
    state: web::Data<AppState>,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = path.into_inner();
    let reviews = state.reviews_repo.for_user(user_id, 50).await?;
    let RatingSummary {
        average_rating,
        review_count,
    } = state.reviews_repo.summary_for_user(user_id).await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<UserReviewsResponse, ErrorBody>::success(
        UserReviewsResponse {
            reviews,
            average_rating,
            review_count,
        },
        "ok",
    )))
}

/// GET /api/v1/reviews/sales/{sale_id}/mine — has the caller already
/// reviewed this sale? (Client-side duplicate prevention + edit UX.)
pub async fn my_review_for_sale(
    state: web::Data<AppState>,
    user: AuthUser,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let review = state
        .reviews_repo
        .find_for_sale(path.into_inner(), user.id)
        .await?;
    Ok(HttpResponse::Ok().json(
        ApiResponse::<Option<ReviewResponse>, ErrorBody>::success(review, "ok"),
    ))
}
