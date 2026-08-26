use actix_web::{HttpResponse, web};
use serde_json::json;
use validator::Validate;

use crate::core::auth::middleware::SuperAdminSession;
use crate::core::auth::password;
use crate::core::error::AppError;
use crate::core::json::ValidatedJson;
use crate::core::response::{ApiResponse, ErrorBody};
use crate::core::state::AppState;
use crate::features::admin_management::dtos::{
    AdminListItem, CreateAdminRequest, CreateAdminResponse, ListAdminsResponse, UpdateAdminRequest,
    UpdateAdminResponse,
};
use crate::features::admin_management::repo::{AdminRow, CreateAdminInput};

fn admin_to_list_item(admin: AdminRow) -> AdminListItem {
    AdminListItem {
        id: admin.id,
        email: admin.email,
        display_name: admin.display_name,
        level: admin.level,
        is_active: admin.is_active,
        created_at: admin.created_at.to_string(),
    }
}

// ---------------------------------------------------------------------------
// POST /api/v1/admin/admins — create a new admin
// ---------------------------------------------------------------------------

pub async fn create_admin(
    session: SuperAdminSession,
    state: web::Data<AppState>,
    body: ValidatedJson<CreateAdminRequest>,
) -> Result<HttpResponse, AppError> {
    body.validate()?;

    let level = body.level.as_deref().unwrap_or("standard");
    if level != "super" && level != "standard" {
        return Err(AppError::BadRequest(
            "level must be 'super' or 'standard'".into(),
        ));
    }

    let default_permissions = serde_json::json!({});
    let permissions = body.permissions.as_ref().unwrap_or(&default_permissions);

    let password_hash = password::hash_password(&body.password)?;

    let mut tx = state.admin_management_repo.begin().await?;

    let admin = state
        .admin_management_repo
        .create_admin(
            &mut tx,
            &CreateAdminInput {
                email: &body.email,
                password_hash: &password_hash,
                display_name: &body.display_name,
                level,
                permissions,
                created_by: session.0.id,
            },
        )
        .await?;

    // Audit log
    state
        .admin_management_repo
        .insert_audit_log(
            &mut tx,
            session.0.id,
            "admin.create",
            Some("admin"),
            Some(&admin.id.to_string()),
            &json!({
                "email": body.email,
                "level": level,
                "created_by": session.0.id,
            }),
        )
        .await?;

    tx.commit().await?;

    Ok(HttpResponse::Created().json(ApiResponse::<CreateAdminResponse, ErrorBody>::success(
        CreateAdminResponse {
            id: admin.id,
            email: admin.email,
            display_name: admin.display_name,
            level: admin.level,
            message: "admin created successfully".to_string(),
        },
        "admin created successfully",
    )))
}

// ---------------------------------------------------------------------------
// GET /api/v1/admin/admins — list all admins
// ---------------------------------------------------------------------------

pub async fn list_admins(
    _session: SuperAdminSession,
    state: web::Data<AppState>,
) -> Result<HttpResponse, AppError> {
    let admins = state.admin_management_repo.list_admins().await?;
    Ok(HttpResponse::Ok().json(ApiResponse::<ListAdminsResponse, ErrorBody>::success(
        ListAdminsResponse {
            admins: admins.into_iter().map(admin_to_list_item).collect(),
        },
        "ok",
    )))
}

// ---------------------------------------------------------------------------
// PATCH /api/v1/admin/admins/{id} — partial update
// ---------------------------------------------------------------------------

pub async fn update_admin(
    session: SuperAdminSession,
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
    body: ValidatedJson<UpdateAdminRequest>,
) -> Result<HttpResponse, AppError> {
    let admin_id = path.into_inner();
    body.validate()?;

    if body
        .level
        .as_ref()
        .is_some_and(|l| l != "super" && l != "standard")
    {
        return Err(AppError::BadRequest(
            "level must be 'super' or 'standard'".into(),
        ));
    }

    // Last super admin guard: check if this update would leave zero active supers
    if body.level.as_deref() == Some("standard") || body.is_active == Some(false) {
        let admins = state.admin_management_repo.list_admins().await?;
        let is_active_super = admins
            .iter()
            .any(|a| a.id == admin_id && a.level == "super" && a.is_active);
        if is_active_super {
            let count = state
                .admin_management_repo
                .count_active_supers_excluding(admin_id)
                .await?;
            if count == 0 {
                return Err(AppError::BadRequest(
                    "cannot deactivate or demote the last super admin".into(),
                ));
            }
        }
    }

    let mut tx = state.admin_management_repo.begin().await?;

    let _admin = state
        .admin_management_repo
        .update_admin(
            &mut tx,
            admin_id,
            body.display_name.as_deref(),
            body.level.as_deref(),
            body.permissions.as_ref(),
            body.is_active,
        )
        .await?;

    state
        .admin_management_repo
        .insert_audit_log(
            &mut tx,
            session.0.id,
            "admin.update",
            Some("admin"),
            Some(&admin_id.to_string()),
            &json!({
                "changed_fields": {
                    "display_name": body.display_name,
                    "level": body.level,
                    "permissions": body.permissions,
                    "is_active": body.is_active,
                },
                "updated_by": session.0.id,
            }),
        )
        .await?;

    tx.commit().await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<UpdateAdminResponse, ErrorBody>::success(
        UpdateAdminResponse {
            message: "admin updated successfully".to_string(),
        },
        "admin updated successfully",
    )))
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/admin/admins/{id} — soft delete
// ---------------------------------------------------------------------------

pub async fn deactivate_admin(
    session: SuperAdminSession,
    state: web::Data<AppState>,
    path: web::Path<uuid::Uuid>,
) -> Result<HttpResponse, AppError> {
    let admin_id = path.into_inner();

    // Last super admin guard
    let admins = state.admin_management_repo.list_admins().await?;
    let is_active_super = admins
        .iter()
        .any(|a| a.id == admin_id && a.level == "super" && a.is_active);
    if is_active_super {
        let count = state
            .admin_management_repo
            .count_active_supers_excluding(admin_id)
            .await?;
        if count == 0 {
            return Err(AppError::BadRequest(
                "cannot deactivate the last super admin".into(),
            ));
        }
    }

    let mut tx = state.admin_management_repo.begin().await?;

    let admin = state
        .admin_management_repo
        .deactivate_admin(&mut tx, admin_id)
        .await?;

    state
        .admin_management_repo
        .insert_audit_log(
            &mut tx,
            session.0.id,
            "admin.deactivate",
            Some("admin"),
            Some(&admin_id.to_string()),
            &json!({
                "email": admin.email,
                "deactivated_by": session.0.id,
            }),
        )
        .await?;

    tx.commit().await?;

    Ok(HttpResponse::Ok().json(ApiResponse::<UpdateAdminResponse, ErrorBody>::success(
        UpdateAdminResponse {
            message: "admin deactivated successfully".to_string(),
        },
        "admin deactivated successfully",
    )))
}
