use actix_web::HttpResponse;
use utoipa::OpenApi;

use crate::core::error::{ErrorResponse, ErrorResponseBody, FieldError};
use crate::features::auth::dtos::*;
use crate::features::auth::dtos::{
    ForgotPasswordRequest, ResendVerificationRequest, ResetPasswordRequest, VerifyOtpRequest,
};
use crate::features::auth::models::UserProfile;
use crate::features::images::dtos::*;
use crate::features::listings::dtos::*;
use crate::features::listings::models::{Condition, ListingStatus};

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

/// Health check — returns 200 if the server is running.
#[utoipa::path(
    get,
    path = "/health",
    tag = "health",
    responses(
        (status = 200, description = "Server is healthy", body = serde_json::Value)
    )
)]
pub async fn health() -> HttpResponse {
    unreachable!("spec only")
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Sign up with a school email address.
///
/// Creates a new user account and sends a verification email.
/// The email domain must belong to a registered partner school.
#[utoipa::path(
    post,
    path = "/api/v1/auth/signup",
    tag = "auth",
    request_body = SignUpRequest,
    responses(
        (status = 201, description = "Account created, verification email sent", body = SignUpResponse),
        (status = 400, description = "Email domain not recognized", body = ErrorResponse),
        (status = 409, description = "Email already registered", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse),
        (status = 429, description = "Rate limit exceeded", body = ErrorResponse)
    )
)]
pub async fn signup() -> HttpResponse {
    unreachable!("spec only")
}

/// Verify an OTP code for email verification or password reset.
///
/// Pass `type: "email_verify"` after signup, or `type: "password_reset"`
/// after requesting a password reset.
#[utoipa::path(
    post,
    path = "/api/v1/auth/verify-otp",
    tag = "auth",
    request_body = VerifyOtpRequest,
    responses(
        (status = 200, description = "OTP verified successfully", body = serde_json::Value),
        (status = 400, description = "Invalid or expired OTP", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse)
    )
)]
pub async fn verify_otp() -> HttpResponse {
    unreachable!("spec only")
}

/// Resend a verification OTP to the given email address.
///
/// Generates a new 6-digit code and invalidates any previous one.
#[utoipa::path(
    post,
    path = "/api/v1/auth/resend-verification",
    tag = "auth",
    request_body = ResendVerificationRequest,
    responses(
        (status = 200, description = "Verification code sent", body = serde_json::Value),
        (status = 400, description = "Email already verified", body = ErrorResponse),
        (status = 404, description = "No account with this email", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse)
    )
)]
pub async fn resend_verification() -> HttpResponse {
    unreachable!("spec only")
}

/// Request a password reset OTP.
///
/// Always returns 200 to prevent user enumeration. If the email exists,
/// a 6-digit code is sent.
#[utoipa::path(
    post,
    path = "/api/v1/auth/forgot-password",
    tag = "auth",
    request_body = ForgotPasswordRequest,
    responses(
        (status = 200, description = "Reset code sent (if account exists)", body = serde_json::Value),
        (status = 422, description = "Validation failed", body = ErrorResponse)
    )
)]
pub async fn forgot_password() -> HttpResponse {
    unreachable!("spec only")
}

/// Reset password using a valid OTP code.
///
/// The OTP must be type `password_reset` and received via the forgot-password flow.
#[utoipa::path(
    post,
    path = "/api/v1/auth/reset-password",
    tag = "auth",
    request_body = ResetPasswordRequest,
    responses(
        (status = 200, description = "Password updated", body = serde_json::Value),
        (status = 400, description = "Invalid or expired OTP", body = ErrorResponse),
        (status = 422, description = "Validation failed (password too short)", body = ErrorResponse)
    )
)]
pub async fn reset_password() -> HttpResponse {
    unreachable!("spec only")
}

/// Log in with email and password.
///
/// Returns an access token (JWT, 15 min TTL) and a refresh token (7 days).
/// Rejects if the email is not verified.
#[utoipa::path(
    post,
    path = "/api/v1/auth/login",
    tag = "auth",
    request_body = LoginRequest,
    responses(
        (status = 200, description = "Login successful", body = LoginResponse),
        (status = 401, description = "Invalid credentials or unverified email", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse),
        (status = 429, description = "Rate limit exceeded", body = ErrorResponse)
    )
)]
pub async fn login() -> HttpResponse {
    unreachable!("spec only")
}

/// Rotate a refresh token.
///
/// Present the old refresh token to receive a new access + refresh pair.
/// Implements token rotation with reuse detection.
#[utoipa::path(
    post,
    path = "/api/v1/auth/refresh",
    tag = "auth",
    request_body = RefreshRequest,
    responses(
        (status = 200, description = "Token rotated successfully", body = RefreshResponse),
        (status = 401, description = "Invalid, expired, or reused refresh token", body = ErrorResponse)
    )
)]
pub async fn refresh() -> HttpResponse {
    unreachable!("spec only")
}

/// Log out by revoking a refresh token.
///
/// Idempotent — always returns 200 regardless of token validity.
#[utoipa::path(
    post,
    path = "/api/v1/auth/logout",
    tag = "auth",
    request_body = LogoutRequest,
    responses(
        (status = 200, description = "Token revoked (or already invalid)")
    )
)]
pub async fn logout() -> HttpResponse {
    unreachable!("spec only")
}

/// Get the current user's profile.
///
/// Requires a valid access token in the Authorization header.
#[utoipa::path(
    get,
    path = "/api/v1/auth/me",
    tag = "auth",
    security(("bearer" = [])),
    responses(
        (status = 200, description = "User profile", body = UserProfile),
        (status = 401, description = "Missing or invalid token", body = ErrorResponse),
        (status = 404, description = "User not found", body = ErrorResponse)
    )
)]
pub async fn me() -> HttpResponse {
    unreachable!("spec only")
}

// ---------------------------------------------------------------------------
// Listings
// ---------------------------------------------------------------------------

/// Create a new listing.
///
/// Requires authentication with a verified email. The seller_id is derived
/// from the authenticated user, never from the request body.
#[utoipa::path(
    post,
    path = "/api/v1/listings",
    tag = "listings",
    security(("bearer" = [])),
    request_body = CreateListingRequest,
    responses(
        (status = 201, description = "Listing created", body = ListingResponse),
        (status = 401, description = "Not authenticated", body = ErrorResponse),
        (status = 403, description = "Email not verified", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse),
        (status = 429, description = "Rate limit exceeded", body = ErrorResponse)
    )
)]
pub async fn create_listing() -> HttpResponse {
    unreachable!("spec only")
}

/// Browse and filter listings with cursor-based pagination.
///
/// Public endpoint — no authentication required. Defaults to active listings.
/// Pass `q` for full-text search ranked by relevance (title weighted above description).
#[utoipa::path(
    get,
    path = "/api/v1/listings",
    tag = "listings",
    params(
        ("q" = Option<String>, Query, description = "Full-text search query (ranks by relevance)"),
        ("category" = Option<i16>, Query, description = "Filter by category ID"),
        ("min_price" = Option<i32>, Query, description = "Minimum price filter"),
        ("max_price" = Option<i32>, Query, description = "Maximum price filter"),
        ("status" = Option<String>, Query, description = "Filter by status (active, reserved, sold)"),
        ("cursor" = Option<String>, Query, description = "Opaque cursor for pagination"),
        ("limit" = Option<i64>, Query, description = "Page size (default 20, max 50)")
    ),
    responses(
        (status = 200, description = "Paginated listing results", body = ListListingsResponse)
    )
)]
pub async fn list_listings() -> HttpResponse {
    unreachable!("spec only")
}

/// Get listing details including seller info, category, and images.
///
/// Public endpoint. Deleted listings are only visible to their owner.
#[utoipa::path(
    get,
    path = "/api/v1/listings/{id}",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID")
    ),
    responses(
        (status = 200, description = "Listing detail", body = ListingDetailResponse),
        (status = 404, description = "Listing not found or deleted", body = ErrorResponse)
    )
)]
pub async fn get_listing_detail() -> HttpResponse {
    unreachable!("spec only")
}

/// Update a listing (partial update).
///
/// Only the owner can edit, and only while the listing is active.
/// Uses double-Option for price: omit = no change, null = set barter-only.
#[utoipa::path(
    patch,
    path = "/api/v1/listings/{id}",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID")
    ),
    request_body = UpdateListingRequest,
    responses(
        (status = 200, description = "Listing updated", body = ListingResponse),
        (status = 403, description = "Not the listing owner", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse),
        (status = 409, description = "Listing is not active", body = ErrorResponse),
        (status = 422, description = "Validation failed", body = ErrorResponse)
    )
)]
pub async fn update_listing() -> HttpResponse {
    unreachable!("spec only")
}

/// Soft-delete a listing.
///
/// Only the owner can delete. Sets status to 'deleted' without removing
/// the row from the database.
#[utoipa::path(
    delete,
    path = "/api/v1/listings/{id}",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID")
    ),
    responses(
        (status = 204, description = "Listing deleted"),
        (status = 403, description = "Not the listing owner", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse)
    )
)]
pub async fn delete_listing() -> HttpResponse {
    unreachable!("spec only")
}

/// Reserve an active listing for purchase.
///
/// Only authenticated users with verified emails can reserve.
/// You cannot reserve your own listing.
#[utoipa::path(
    post,
    path = "/api/v1/listings/{id}/reserve",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID to reserve")
    ),
    responses(
        (status = 200, description = "Listing reserved", body = ListingResponse),
        (status = 400, description = "Cannot reserve your own listing", body = ErrorResponse),
        (status = 401, description = "Not authenticated", body = ErrorResponse),
        (status = 403, description = "Email not verified", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse),
        (status = 409, description = "Listing is no longer available", body = ErrorResponse)
    )
)]
pub async fn reserve_listing() -> HttpResponse {
    unreachable!("spec only")
}

/// Mark a reserved listing as sold.
///
/// Only the seller can mark a listing as sold. The listing must be
/// in 'reserved' status.
#[utoipa::path(
    post,
    path = "/api/v1/listings/{id}/mark-sold",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID")
    ),
    responses(
        (status = 200, description = "Listing marked as sold", body = ListingResponse),
        (status = 403, description = "Not the listing seller", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse),
        (status = 409, description = "Listing must be reserved first", body = ErrorResponse)
    )
)]
pub async fn mark_sold() -> HttpResponse {
    unreachable!("spec only")
}

/// Cancel a reservation and return the listing to active status.
///
/// Either the seller or the reserving buyer can unreserve.
#[utoipa::path(
    post,
    path = "/api/v1/listings/{id}/unreserve",
    tag = "listings",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Listing ID")
    ),
    responses(
        (status = 200, description = "Reservation cancelled", body = ListingResponse),
        (status = 403, description = "Not authorized to unreserve", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse),
        (status = 409, description = "Listing is not reserved", body = ErrorResponse)
    )
)]
pub async fn unreserve_listing() -> HttpResponse {
    unreachable!("spec only")
}

// ---------------------------------------------------------------------------
// Images (Epic 6)
// ---------------------------------------------------------------------------

/// Get a presigned URL for direct image upload to cloud storage.
///
/// The backend never proxies image bytes. Instead it hands the client a
/// short-lived PUT URL for uploading directly to Backblaze B2.
///
/// Enforces max 3 images per listing. Only the listing owner can request
/// a presign. Content type must be `image/jpeg`, `image/png`, or `image/webp`.
#[utoipa::path(
    post,
    path = "/api/v1/images/presign",
    tag = "images",
    security(("bearer" = [])),
    request_body = PresignRequest,
    responses(
        (status = 200, description = "Presigned upload URL issued", body = PresignResponse),
        (status = 401, description = "Not authenticated", body = ErrorResponse),
        (status = 403, description = "Not the listing owner", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse),
        (status = 422, description = "Validation failed (e.g. unsupported content type)", body = ErrorResponse)
    )
)]
pub async fn presign_image() -> HttpResponse {
    unreachable!("spec only")
}

/// Confirm that an image upload completed successfully.
///
/// After the client uploads to the presigned URL, it calls this endpoint.
/// The server performs a HEAD check against B2 to verify the object exists
/// and is within size limits (max 10 MiB) before inserting the DB row.
#[utoipa::path(
    post,
    path = "/api/v1/images/confirm",
    tag = "images",
    security(("bearer" = [])),
    request_body = ConfirmRequest,
    responses(
        (status = 201, description = "Image registered", body = ConfirmResponse),
        (status = 400, description = "Object not found in storage or file too large", body = ErrorResponse),
        (status = 401, description = "Not authenticated", body = ErrorResponse),
        (status = 403, description = "Not the listing owner", body = ErrorResponse),
        (status = 404, description = "Listing not found", body = ErrorResponse)
    )
)]
pub async fn confirm_image() -> HttpResponse {
    unreachable!("spec only")
}

/// Delete an image from a listing.
///
/// Only the listing owner can delete. Removes both the DB row and the
/// underlying object from cloud storage (best-effort cleanup).
#[utoipa::path(
    delete,
    path = "/api/v1/images/{id}",
    tag = "images",
    security(("bearer" = [])),
    params(
        ("id" = uuid::Uuid, Path, description = "Image ID")
    ),
    responses(
        (status = 204, description = "Image deleted"),
        (status = 401, description = "Not authenticated", body = ErrorResponse),
        (status = 403, description = "Not the listing owner", body = ErrorResponse),
        (status = 404, description = "Image not found", body = ErrorResponse)
    )
)]
pub async fn delete_image() -> HttpResponse {
    unreachable!("spec only")
}

// ---------------------------------------------------------------------------
// OpenAPI document
// ---------------------------------------------------------------------------

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Uni-Stash API",
        description = "Campus Marketplace backend API. Browse, list, and trade items with fellow students.",
        version = "0.1.0",
        contact(name = "Uni-Stash Team"),
        license(name = "MIT")
    ),
    paths(
        health,
        // Auth
        signup,
        verify_otp,
        resend_verification,
        forgot_password,
        reset_password,
        login,
        refresh,
        logout,
        me,
        // Listings
        create_listing,
        list_listings,
        get_listing_detail,
        update_listing,
        delete_listing,
        reserve_listing,
        mark_sold,
        unreserve_listing,
        // Images
        presign_image,
        confirm_image,
        delete_image,
    ),
    components(schemas(
        // Auth
        SignUpRequest,
        SignUpResponse,
        VerifyOtpRequest,
        ResendVerificationRequest,
        ForgotPasswordRequest,
        ResetPasswordRequest,
        LoginRequest,
        LoginResponse,
        RefreshRequest,
        RefreshResponse,
        LogoutRequest,
        UserProfile,
        // Listings
        CreateListingRequest,
        ListingResponse,
        ListListingsQuery,
        ListListingsResponse,
        ListingSummary,
        ListingDetailResponse,
        SellerSummary,
        CategorySummary,
        ImageSummary,
        UpdateListingRequest,
        // Images
        PresignRequest,
        PresignResponse,
        ConfirmRequest,
        ConfirmResponse,
        // Shared
        Condition,
        ListingStatus,
        FieldError,
        ErrorResponse,
        ErrorResponseBody,
    )),
    tags(
        (name = "health", description = "Health check"),
        (name = "auth", description = "Authentication and account management"),
        (name = "listings", description = "Listing CRUD, browsing, search, and state machine"),
        (name = "images", description = "Image upload pipeline (presign, confirm, delete)")
    )
)]
pub struct ApiDoc;
