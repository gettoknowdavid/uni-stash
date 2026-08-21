use actix_web::HttpResponse;
use utoipa::OpenApi;

use crate::core::error::{ErrorResponse, ErrorResponseBody, FieldError};
use crate::features::auth::dtos::*;
use crate::features::auth::models::UserProfile;
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

/// Verify email address using the token sent to the user's inbox.
#[utoipa::path(
    post,
    path = "/api/v1/auth/verify-email",
    tag = "auth",
    request_body = VerifyEmailRequest,
    responses(
        (status = 200, description = "Email verified successfully"),
        (status = 401, description = "Invalid or expired token", body = ErrorResponse)
    )
)]
pub async fn verify_email() -> HttpResponse {
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
#[utoipa::path(
    get,
    path = "/api/v1/listings",
    tag = "listings",
    params(
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
        signup,
        verify_email,
        login,
        refresh,
        logout,
        me,
        create_listing,
        list_listings,
        get_listing_detail,
        update_listing,
        delete_listing,
        reserve_listing,
        mark_sold,
        unreserve_listing,
    ),
    components(schemas(
        // Auth
        SignUpRequest,
        SignUpResponse,
        VerifyEmailRequest,
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
        // Shared
        Condition,
        ListingStatus,
        FieldError,
        ErrorResponse,
        ErrorResponseBody,
    )),
    tags(
        (name = "health", description = "Health check endpoints"),
        (name = "auth", description = "Authentication and account management"),
        (name = "listings", description = "Listing CRUD, browsing, and state machine")
    )
)]
pub struct ApiDoc;
