use actix_web::{HttpResponse, web};
use serde_json::json;
use validator::Validate;

use crate::core::auth::middleware::AdminSession;
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::state::AppState;
use crate::features::schools::dtos::{
    CreateSchoolRequest, CreateSchoolResponse, ListSchoolsQuery, ListSchoolsResponse,
    SchoolResponse, UpdateSchoolRequest,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn school_to_response(school: crate::features::auth::models::School) -> SchoolResponse {
    SchoolResponse {
        id: school.id,
        name: school.name,
        domain: school.domain,
        created_at: school.created_at.to_string(),
    }
}

// ---------------------------------------------------------------------------
// GET /api/v1/schools — public, list all schools
// ---------------------------------------------------------------------------

pub async fn list_schools(
    state: web::Data<AppState>,
    query: web::Query<ListSchoolsQuery>,
) -> Result<HttpResponse, AppError> {
    let schools = state
        .schools_repo
        .list_schools(query.search.as_deref())
        .await?;

    Ok(HttpResponse::Ok().json(ListSchoolsResponse {
        schools: schools.into_iter().map(school_to_response).collect(),
    }))
}

// ---------------------------------------------------------------------------
// GET /api/v1/schools/{id} — public, get single school
// ---------------------------------------------------------------------------

pub async fn get_school(
    state: web::Data<AppState>,
    path: web::Path<i16>,
) -> Result<HttpResponse, AppError> {
    let school_id = path.into_inner();
    let school = state
        .schools_repo
        .find_school_by_id(school_id)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("school with id {school_id} not found")))?;

    Ok(HttpResponse::Ok().json(school_to_response(school)))
}

// ---------------------------------------------------------------------------
// POST /api/v1/schools — admin-only, create a new school
// ---------------------------------------------------------------------------

pub async fn create_school(
    session: AdminSession,
    state: web::Data<AppState>,
    body: ValidatedJson<CreateSchoolRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    if !session.can("schools", "write") {
        return Err(AppError::Forbidden);
    }

    let school = state
        .schools_repo
        .create_school(&body.name, &body.domain)
        .await?;

    Ok(HttpResponse::Created().json(CreateSchoolResponse {
        id: school.id,
        name: school.name,
        domain: school.domain,
        message: "school created successfully".to_string(),
    }))
}

// ---------------------------------------------------------------------------
// PATCH /api/v1/schools/{id} — admin-only, update a school
// ---------------------------------------------------------------------------

pub async fn update_school(
    session: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<i16>,
    body: ValidatedJson<UpdateSchoolRequest>,
) -> Result<HttpResponse, AppError> {
    let school_id = path.into_inner();
    body.validate()?;

    if !session.can("schools", "write") {
        return Err(AppError::Forbidden);
    }

    // Ensure at least one field is being updated
    if body.name.is_none() && body.domain.is_none() {
        return Err(AppError::BadRequest(
            "at least one of 'name' or 'domain' must be provided".to_string(),
        ));
    }

    let school = state
        .schools_repo
        .update_school(school_id, body.name.as_deref(), body.domain.as_deref())
        .await?;

    Ok(HttpResponse::Ok().json(json!({
        "message": "school updated successfully",
        "school": school_to_response(school),
    })))
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/schools/{id} — admin-only, delete a school
// ---------------------------------------------------------------------------

pub async fn delete_school(
    session: AdminSession,
    state: web::Data<AppState>,
    path: web::Path<i16>,
) -> Result<HttpResponse, AppError> {
    let school_id = path.into_inner();

    if !session.can("schools", "write") {
        return Err(AppError::Forbidden);
    }

    state.schools_repo.delete_school(school_id).await?;

    Ok(HttpResponse::NoContent().finish())
}
