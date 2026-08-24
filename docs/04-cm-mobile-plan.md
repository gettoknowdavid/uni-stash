# UniStash Mobile — Implementation Plan

> **Date:** August 24, 2026
> **Status:** Approved — ready for implementation
> **Scope:** Flutter mobile client for the UniStash campus marketplace
> **Deviation from TRD:** Signals for state management (replacing Riverpod), GoRouter for routing, Retrofit+Dio for HTTP

---

## Table of Contents

1. [Current State Assessment](#1-current-state-assessment)
2. [Tech Stack & Dependencies](#2-tech-stack--dependencies)
3. [Project Architecture](#3-project-architecture)
4. [Implementation Order](#4-implementation-order)
5. [Consistency Guidelines](#5-consistency-guidelines)
6. [Testing Strategy](#6-testing-strategy)
7. [Build Phases Summary](#7-build-phases-summary)

---

## 1. Current State Assessment

### Backend (what exists)

| Feature | Status | Endpoints |
|---------|--------|-----------|
| Auth | Done | signup, verify-otp, resend-verification, forgot-password, reset-password, login, refresh, logout, me |
| Listings | Done | CRUD, browse/search/filter, detail, reserve/mark-sold/unreserve state machine |
| Images | Done | presign, confirm, delete |
| Schools | Done | CRUD (public read + admin write) |
| Admin Auth | Done | Admin token refresh |
| Admin Management | Done | Admin user management |
| **Chats** | **Missing** | REST + WebSocket (Epics 8-9) |
| **Reports** | **Missing** | Submit + admin review (Epic 10) |
| **Categories** | **Missing** | No `GET /categories` endpoint (flagged gap CM-11.7) |

### Mobile (current state)

- Bare Flutter scaffold at `apps/mobile/`
- Only `main.dart` with `MaterialApp` showing "Hello World!!"
- `pubspec.yaml` depends on `material_ui` (needs replacing with ForUI)
- No routing, no state management, no API client, no features

### Backend API Shape (from codebase)

The backend uses these conventions (TRD 2.1):

- **Base path:** `/api/v1`
- **Auth:** `Authorization: Bearer <access_token>` (JWT), except `/auth/*` public endpoints
- **Bodies:** JSON
- **Pagination:** cursor-based (`?cursor=<opaque>&limit=20`)
- **Error shape:** `{ "error": { "code": "...", "message": "..." } }`
- **Validation errors:** 422 with field-level errors

Key response shapes:

```
POST /auth/login
{ "access_token": "...", "refresh_token": "...", "expires_in": 86400 }

GET /auth/me
{ "id": "uuid", "email": "...", "display_name": "...", "email_verified": true, "role": "student" }

GET /listings (browse)
{
  "listings": [{ "id": "uuid", "title": "...", "price": 1500, "condition": "used", "status": "active", "created_at": "..." }],
  "next_cursor": "opaque_string_or_null"
}

GET /listings/{id} (detail)
{
  "id": "uuid", "title": "...", "description": "...", "price": 1500,
  "condition": "used", "status": "active", "created_at": "...",
  "seller": { "id": "uuid", "display_name": "..." },
  "category": { "id": 1, "slug": "electronics", "label": "Electronics" },
  "images": [{ "id": "uuid", "object_key": "...", "position": 0 }]
}

POST /images/presign
{ "upload_url": "https://r2...", "object_key": "listings/uuid/img_0.jpg", "position": 0 }

POST /images/confirm
{ "id": "uuid", "listing_id": "uuid", "object_key": "...", "position": 0, "created_at": "..." }
```

---

## 2. Tech Stack & Dependencies

### Core Framework

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK ^3.13.0 | Framework |
| `forui` | ^0.22.0 | Design system / UI components (TRD 5) |
| `forui_assets` | ^0.1.0 | Lucide icons companion package |
| `go_router` | ^15.0.0 | Declarative routing with deep link support |
| `signals` | ^7.1.0 | Fine-grained reactive state management |
| `signals_flutter` | ^7.1.0 | Flutter bindings for signals (SignalWidget, etc.) |

### Networking

| Package | Version | Purpose |
|---------|---------|---------|
| `dio` | ^5.7.0 | HTTP client with interceptors |
| `retrofit` | ^4.0.0 | Type-safe REST client (code-gen on top of Dio) |
| `web_socket_channel` | ^3.0.0 | WebSocket for real-time chat |
| `freezed_annotation` | ^2.4.0 | Immutable model serialization |

### Storage & Utilities

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_secure_storage` | ^9.0.0 | Secure token storage (Keychain/Keystore) |
| `json_annotation` | ^4.9.0 | JSON serialization annotations |
| `cached_network_image` | ^3.4.0 | Image caching for listing photos |
| `image_picker` | ^1.1.0 | Camera/gallery image selection |
| `timeago` | ^3.7.0 | Relative timestamps ("2 hours ago") |
| `envied` | ^1.0.0 | Type-safe environment variable access |
| `connectivity_plus` | ^6.0.0 | Network status detection |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `build_runner` | ^2.4.0 | Code generation runner |
| `freezed` | ^2.5.0 | Immutable model code generation |
| `json_serializable` | ^6.8.0 | JSON code generation |
| `retrofit_generator` | ^8.0.0 | Retrofit code generation |
| `mockito` | ^5.4.0 | Mocking for unit tests |
| `mocktail` | ^1.0.0 | Mocking alternative |

> **Note:** Remove `material_ui` from current `pubspec.yaml` — it's replaced by `forui`.

---

## 3. Project Architecture

### Design Principles

1. **Feature-first, vertical slices** — mirrors the backend's `features/` layout per TRD 1.4
2. **Signals for state** — fine-grained reactivity without Provider/Riverpod nesting overhead
3. **GoRouter for navigation** — declarative, URL-based, supports deep links
4. **Retrofit + Dio for networking** — type-safe API client with automatic code generation
5. **Freezed for models** — immutable, copyWith, equality, serialization
6. **Clean separation** — core is shared infrastructure, features own their UI + logic

### Folder Structure

```
apps/mobile/
├── lib/
│   ├── main.dart
│   │
│   ├── core/
│   │   ├── api/
│   │   │   ├── api_client.dart             # Dio setup, base URL, interceptors
│   │   │   ├── api_error.dart              # Unified error type
│   │   │   ├── auth_interceptor.dart       # Token injection + 401 refresh logic
│   │   │   └── api_client.g.dart           # Generated retrofit client
│   │   │
│   │   ├── auth/
│   │   │   ├── token_storage.dart          # Secure read/write/refresh of tokens
│   │   │   ├── auth_state.dart             # Signal: current auth status
│   │   │   └── auth_guard.dart             # GoRouter redirect logic
│   │   │
│   │   ├── config/
│   │   │   ├── env.dart                    # Envied-based env vars
│   │   │   └── constants.dart              # App-wide constants
│   │   │
│   │   ├── storage/
│   │   │   └── secure_storage.dart         # Wrapper around flutter_secure_storage
│   │   │
│   │   ├── router/
│   │   │   ├── app_router.dart             # GoRouter configuration
│   │   │   └── route_names.dart            # Named route constants
│   │   │
│   │   ├── theme/
│   │   │   ├── app_theme.dart              # ForUI FTheme configuration
│   │   │   └── color_schemes.dart          # Light/dark color schemes
│   │   │
│   │   ├── utils/
│   │   │   ├── formatters.dart             # Price formatting, date formatting
│   │   │   ├── validators.dart             # Client-side form validation helpers
│   │   │   └── extensions.dart             # Dart/Flutter type extensions
│   │   │
│   │   └── widgets/
│   │       ├── app_scaffold.dart           # Bottom nav shell
│   │       ├── error_view.dart             # Reusable error state widget
│   │       ├── empty_view.dart             # Reusable empty state widget
│   │       ├── loading_view.dart           # Reusable loading spinner/skeleton
│   │       ├── image_carousel.dart         # Listing image display (cached)
│   │       ├── price_tag.dart              # Price/barter display
│   │       └── confirm_dialog.dart         # Reusable confirmation dialog
│   │
│   └── features/
│       ├── auth/
│       │   ├── models/
│       │   │   └── user.dart               # User model (Freezed)
│       │   ├── data/
│       │   │   ├── auth_api.dart           # Retrofit auth endpoints
│       │   │   └── auth_repository.dart    # Auth data access
│       │   ├── states/
│       │   │   └── auth_state.dart         # Signals: auth status, current user
│       │   └── screens/
│       │       ├── login_screen.dart
│       │       ├── signup_screen.dart
│       │       └── verify_otp_screen.dart
│       │
│       ├── listings/
│       │   ├── models/
│       │   │   ├── listing.dart            # Listing, ListingStatus, Condition, ListingDetail
│       │   │   └── category.dart           # Category model
│       │   ├── data/
│       │   │   ├── listings_api.dart       # Retrofit listings endpoints
│       │   │   ├── listings_repository.dart
│       │   │   └── categories_repository.dart
│       │   ├── states/
│       │   │   ├── listings_state.dart     # Signals: browse list, search, pagination
│       │   │   └── listing_detail_state.dart
│       │   └── screens/
│       │       ├── browse_screen.dart
│       │       ├── listing_detail_screen.dart
│       │       ├── create_listing_screen.dart
│       │       └── edit_listing_screen.dart
│       │
│       ├── images/
│       │   └── data/
│       │       ├── images_api.dart         # Retrofit image endpoints
│       │       └── images_repository.dart  # Presign -> upload to R2 -> confirm
│       │
│       ├── chats/
│       │   ├── models/
│       │   │   └── chat_thread.dart        # ChatThread, Message, WsMessage
│       │   ├── data/
│       │   │   ├── chats_api.dart          # Retrofit chat REST endpoints
│       │   │   ├── chats_repository.dart   # REST-backed thread list + history
│       │   │   └── chat_ws_client.dart     # WebSocket client
│       │   ├── states/
│       │   │   ├── chat_threads_state.dart
│       │   │   ├── chat_messages_state.dart
│       │   │   └── ws_connection_state.dart
│       │   └── screens/
│       │       ├── chat_threads_screen.dart
│       │       └── chat_detail_screen.dart
│       │
│       └── profile/
│           ├── data/
│           │   └── profile_api.dart
│           ├── states/
│           │   └── profile_state.dart
│           └── screens/
│               └── profile_screen.dart
│
├── test/
│   ├── core/
│   │   ├── api/
│   │   │   └── auth_interceptor_test.dart
│   │   └── auth/
│   │       └── token_storage_test.dart
│   ├── features/
│   │   ├── auth/
│   │   │   └── auth_repository_test.dart
│   │   ├── listings/
│   │   │   ├── listings_repository_test.dart
│   │   │   └── listings_state_test.dart
│   │   └── chats/
│   │       ├── chats_repository_test.dart
│   │       └── chat_ws_client_test.dart
│   └── helpers/
│       ├── test_app.dart
│       └── mock_data.dart
│
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

### Why This Structure Scales

| Concern | How it's handled |
|---------|-----------------|
| Adding a new feature | Create `features/<name>/` with `models/`, `data/`, `states/`, `screens/` — zero changes to other features |
| Shared UI | Goes in `core/widgets/` — only truly cross-feature widgets live here |
| API contract changes | Retrofit code-gen regenerates `*.g.dart` files — type safety across the whole app |
| State complexity | Signals compose naturally — a feature can have multiple fine-grained signals without provider nesting |
| Testing | Each layer is independently testable: models (pure Dart), repositories (mock API), states (mock repository), screens (widget tests) |
| Backend/frontend sync | `features/` mirrors backend's `features/` by name (auth, listings, chats, images) per TRD 1.4 |

---

## 4. Implementation Order

### Phase 1: Core Infrastructure

Everything else depends on this. Build it first and build it well.

#### Step 1.1 — Project cleanup & dependencies

**Files to modify:**
- `apps/mobile/pubspec.yaml` — replace `material_ui` with all dependencies from section 2
- `apps/mobile/analysis_options.yaml` — update lint config

**What to do:**
- Remove `material_ui` dependency
- Add all production and dev dependencies
- Run `flutter pub get`
- Verify clean `flutter analyze`

#### Step 1.2 — Core: Environment & Config

**Files to create:**
- `lib/core/config/env.dart` — envied-based typed env vars
  - `BASE_URL` (backend API)
  - `WS_URL` (WebSocket base)
  - `ENV` (dev/staging/prod)
- `lib/core/config/constants.dart` — app-wide constants
  - Token refresh buffer (60 seconds before expiry)
  - Max images per listing (3)
  - Default page size (20)
  - Rate limit thresholds

#### Step 1.3 — Core: Theme (ForUI)

**Files to create:**
- `lib/core/theme/app_theme.dart` — `FThemeData` configuration
  - Light + dark theme support (auto-detect system preference)
  - Color scheme matching UniStash branding
  - Typography scale
- `lib/core/theme/color_schemes.dart` — color definitions

**Rules:**
- Always use `FTheme.of(context)` for theme data, never raw `Theme.of(context)`
- Use ForUI's `FApp` as the root widget (replaces `MaterialApp`)

#### Step 1.4 — Core: Router (GoRouter)

**Files to create:**
- `lib/core/router/app_router.dart` — GoRouter configuration
- `lib/core/router/route_names.dart` — named route constants

**Route tree:**
```
/login                                    -> LoginScreen (public)
/signup                                   -> SignupScreen (public)
/verify-otp                               -> VerifyOtpScreen (public)
/                                         -> ShellRoute (bottom nav, auth required)
  /browse                                 -> BrowseScreen (listings feed)
  /chat                                   -> ChatThreadsScreen (inbox)
  /profile                                -> ProfileScreen
/listings/create                          -> CreateListingScreen
/listings/:id                             -> ListingDetailScreen
/listings/:id/edit                        -> EditListingScreen
/chats/:id                                -> ChatDetailScreen
```

**Auth redirect logic:**
- Unauthenticated users -> forced to `/login`
- Authenticated users on `/login` or `/signup` -> redirected to `/`
- Auth state changes trigger router refresh

#### Step 1.5 — Core: API Client (Retrofit + Dio)

**Files to create:**
- `lib/core/api/api_client.dart` — Dio instance configuration
  - Base URL from env
  - Timeout configuration (connect: 15s, receive: 30s)
  - Logging interceptor (dev only)
  - Auth interceptor attachment
- `lib/core/api/auth_interceptor.dart` — Token injection + refresh logic
  - Reads access token from secure storage
  - Adds `Authorization: Bearer <token>` header
  - On 401: trigger refresh, retry original request once
  - Concurrent refresh deduplication (single in-flight refresh Future)
  - On refresh failure: clear tokens, redirect to login
- `lib/core/api/api_error.dart` — Unified error type
  - `ApiError` class with status code, error code, message
  - Maps to backend's `{ "error": { "code", "message" } }` shape
  - Field-level validation errors preserved for form display
- Generated `api_client.g.dart` from Retrofit annotations

**Key design — the 401 refresh interceptor:**

```dart
// Pseudocode for the critical refresh logic
class AuthInterceptor extends Interceptor {
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  @override
  void onRequest(options, handler) async {
    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(dioException, handler) async {
    if (dioException.response?.statusCode == 401) {
      if (_isRefreshing) {
        // Wait for in-flight refresh
        final newToken = await _refreshCompleter!.future;
        // Retry with new token
        return handler.resolve(await _retry(dioException.requestOptions, newToken));
      }
      _isRefreshing = true;
      _refreshCompleter = Completer();
      try {
        final newToken = await _refresh();
        _refreshCompleter!.complete(newToken);
        return handler.resolve(await _retry(dioException.requestOptions, newToken));
      } catch (e) {
        _refreshCompleter!.complete(null);
        await _tokenStorage.clearAll();
        _router.go('/login');
        return handler.next(dioException);
      } finally {
        _isRefreshing = false;
        _refreshCompleter = null;
      }
    }
    handler.next(dioException);
  }
}
```

#### Step 1.6 — Core: Auth State & Token Storage

**Files to create:**
- `lib/core/storage/secure_storage.dart` — `flutter_secure_storage` wrapper
  - Store/retrieve: access token, refresh token, refresh expiry
  - Clear all on logout
- `lib/core/auth/token_storage.dart` — higher-level token management
- `lib/core/auth/auth_state.dart` — Signals-based auth state
  - `Signal<AuthStatus>` (enum: unauthenticated, authenticated, loading)
  - `Computed<User?>` derived from auth status
  - `login()`, `logout()`, `refreshSession()` actions
- `lib/core/auth/auth_guard.dart` — GoRouter redirect based on auth state

**Signal pattern:**
```dart
enum AuthStatus { unauthenticated, authenticated, loading }

final authStatus = signal(AuthStatus.loading);
final currentUser = signal<User?>(null);
final isLoggedIn = computed(() => authStatus.value == AuthStatus.authenticated);

Future<void> login(String email, String password) async {
  authStatus.value = AuthStatus.loading;
  try {
    final response = await authApi.login(LoginRequest(email: email, password: password));
    await tokenStorage.saveTokens(response.accessToken, response.refreshToken, response.expiresIn);
    final user = await authApi.getMe();
    currentUser.value = user;
    authStatus.value = AuthStatus.authenticated;
  } catch (e) {
    authStatus.value = AuthStatus.unauthenticated;
    rethrow;
  }
}
```

#### Step 1.7 — Core: Shared Widgets

**Files to create:**
- `lib/core/widgets/error_view.dart` — error state with retry button
- `lib/core/widgets/empty_view.dart` — empty state illustration + message
- `lib/core/widgets/loading_view.dart` — loading spinner / skeleton
- `lib/core/widgets/image_carousel.dart` — cached image display with page indicator
- `lib/core/widgets/price_tag.dart` — price display (amount or "Barter")
- `lib/core/widgets/confirm_dialog.dart` — reusable confirmation dialog
- `lib/core/widgets/app_scaffold.dart` — bottom navigation shell with GoRouter

#### Step 1.8 — Core: Utilities

**Files to create:**
- `lib/core/utils/formatters.dart` — price formatting, relative dates (timeago)
- `lib/core/utils/validators.dart` — email, password, name validation (mirrors server rules)
- `lib/core/utils/extensions.dart` — useful Dart/Flutter extensions

---

### Phase 2: Auth Feature

First real feature. Gates everything — must work before any other screen is accessible.

#### Step 2.1 — Auth Models

**Files to create:**
- `lib/features/auth/models/user.dart` — Freezed model matching `GET /auth/me` response

```dart
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String email,
    required String displayName,
    required bool emailVerified,
    required String role,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

#### Step 2.2 — Auth API & Repository

**Files to create:**
- `lib/features/auth/data/auth_api.dart` — Retrofit interface

```dart
@RestApi(baseUrl: '')
abstract class AuthApi {
  factory AuthApi(Dio dio, {String baseUrl}) = _AuthApi;

  @POST('/auth/signup')
  Future<SignUpResponse> signup(@Body() SignUpRequest request);

  @POST('/auth/verify-otp')
  Future<VerifyOtpResponse> verifyOtp(@Body() VerifyOtpRequest request);

  @POST('/auth/resend-verification')
  Future<void> resendVerification(@Body() ResendVerificationRequest request);

  @POST('/auth/forgot-password')
  Future<void> forgotPassword(@Body() ForgotPasswordRequest request);

  @POST('/auth/reset-password')
  Future<void> resetPassword(@Body() ResetPasswordRequest request);

  @POST('/auth/login')
  Future<LoginResponse> login(@Body() LoginRequest request);

  @POST('/auth/refresh')
  Future<RefreshResponse> refresh(@Body() RefreshRequest request);

  @POST('/auth/logout')
  Future<void> logout(@Body() LogoutRequest request);

  @GET('/auth/me')
  Future<UserProfile> getMe();
}
```

- `lib/features/auth/data/auth_repository.dart` — orchestrates API calls + token storage

#### Step 2.3 — Auth State (Signals)

**Files to create:**
- `lib/features/auth/states/auth_state.dart`
  - `authStatus` signal (unauthenticated/authenticated/loading)
  - `currentUser` computed signal
  - `signup()`, `login()`, `logout()`, `verifyOtp()` actions
  - Error state for form submissions

#### Step 2.4 — Auth Screens

**Files to create:**
- `lib/features/auth/screens/login_screen.dart`
  - Email + password form using ForUI `FTextField`, `FButton`
  - "Don't have an account?" -> navigate to signup
  - "Forgot password?" -> forgot password flow
  - Error handling: wrong credentials vs email not verified
- `lib/features/auth/screens/signup_screen.dart`
  - Email + password + display name form
  - Client-side validation mirrors server rules
  - Success -> navigate to OTP verification
- `lib/features/auth/screens/verify_otp_screen.dart`
  - 6-digit OTP input
  - Resend verification option
  - Success -> navigate to main app

---

### Phase 3: Listings Feature

Core marketplace object. Browse, search, create, edit, reserve.

#### Step 3.1 — Listings Models

**Files to create:**
- `lib/features/listings/models/listing.dart` — Freezed models for Listing, ListingDetail, ListingStatus, Condition, SellerSummary, CategorySummary, ImageSummary
- `lib/features/listings/models/category.dart` — Category model

#### Step 3.2 — Listings API & Repository

**Files to create:**
- `lib/features/listings/data/listings_api.dart` — Retrofit interface
  - `GET /listings` (query params: q, category, min_price, max_price, status, cursor, limit)
  - `GET /listings/{id}` -> ListingDetail
  - `POST /listings` -> ListingResponse
  - `PATCH /listings/{id}` -> ListingResponse
  - `DELETE /listings/{id}` -> void
  - `POST /listings/{id}/reserve` -> Listing
  - `POST /listings/{id}/mark-sold` -> Listing
  - `POST /listings/{id}/unreserve` -> Listing
- `lib/features/listings/data/listings_repository.dart`
- `lib/features/listings/data/categories_repository.dart` — `GET /categories` (new backend endpoint, see Phase 6)

#### Step 3.3 — Listings State (Signals)

**Files to create:**
- `lib/features/listings/states/listings_state.dart`
  - `listings` signal, `hasMore`, `isLoading`, `selectedCategory`, `searchQuery`
  - `loadMore()`, `refresh()`, `search(query)`
- `lib/features/listings/states/listing_detail_state.dart`
  - `listing` signal, `isLoading`
  - `reserve()`, `markSold()`, `unreserve()` actions

#### Step 3.4 — Listings Screens

**Files to create:**
- `lib/features/listings/screens/browse_screen.dart` — search bar, category filter chips, listing grid with infinite scroll, pull-to-refresh
- `lib/features/listings/screens/listing_detail_screen.dart` — image carousel, price, seller info, category badge, action buttons (reserve/edit/delete based on role+status), "Chat with seller" button
- `lib/features/listings/screens/create_listing_screen.dart` — title, description, category picker, price (optional for barter), condition picker, image picker (up to 3)
- `lib/features/listings/screens/edit_listing_screen.dart` — pre-filled form (active-only), image management

---

### Phase 4: Image Upload Flow

Wires into listing create/edit. Client uploads directly to R2.

#### Step 4.1 — Images API & Repository

**Files to create:**
- `lib/features/images/data/images_api.dart` — Retrofit interface (presign, confirm, delete)
- `lib/features/images/data/images_repository.dart`
  - `uploadImage(listingId, file, contentType)` — full presign -> upload -> confirm flow
  - **Upload goes directly to R2 presigned URL** (NOT through backend API client)
  - Progress tracking per image
  - Retry on failure

#### Step 4.2 — Image Upload Integration

- Wire into listing create/edit screens
- Progress indicators per image
- Error handling per image
- Maximum 3 images enforcement client-side

---

### Phase 5: Chat Feature

Requires backend Epics 8-9. Can be stubbed/prepared in parallel.

#### Step 5.1 — Chat Models

**Files to create:**
- `lib/features/chats/models/chat_thread.dart` — ChatThread, Message, WsMessage (typed union)

#### Step 5.2 — Chat REST API & Repository

**Files to create:**
- `lib/features/chats/data/chats_api.dart` — Retrofit interface
  - `GET /chats` -> List<ChatThread>
  - `GET /chats/{id}/messages` -> List<Message> (cursor-paginated, newest first)
  - `POST /chats` -> ChatThread (idempotent, body: `{ listing_id }`)
- `lib/features/chats/data/chats_repository.dart`

#### Step 5.3 — WebSocket Client

**Files to create:**
- `lib/features/chats/data/chat_ws_client.dart`
  - Connect to `/ws/chats?token=<access_token>`
  - Handle server pings (respond with pong)
  - Send messages: `{ "type": "send", "chat_id": "...", "body": "..." }`
  - Receive messages: typed message parsing
  - Reconnect with exponential backoff (1s -> 2s -> 4s -> 8s -> max 30s)
  - Sync on reconnect: `{ "type": "sync", "since": "..." }`
  - Token refresh handling: reconnect with fresh token when access token expires
  - Connection state signals: connected / connecting / disconnected

#### Step 5.4 — Chat State (Signals)

**Files to create:**
- `lib/features/chats/states/chat_threads_state.dart` — thread list, unread counts, optimistic updates
- `lib/features/chats/states/chat_messages_state.dart` — messages for active thread, sendMessage, loadMore
- `lib/features/chats/states/ws_connection_state.dart` — connection status, auto-reconnect

#### Step 5.5 — Chat Screens

**Files to create:**
- `lib/features/chats/screens/chat_threads_screen.dart` — thread list with counterpart name, listing thumbnail, last message preview, unread badge, timestamp
- `lib/features/chats/screens/chat_detail_screen.dart` — message bubbles, message input, infinite scroll upward, real-time WS display, connection status indicator

---

### Phase 6: Backend Gaps

Small addendum tickets needed for full mobile functionality.

#### CM-4.9 — `GET /categories` endpoint
- Simple public endpoint returning all categories ordered by `sort_order`
- No auth required
- Response: `{ categories: [{ id: 1, slug: "electronics", label: "Electronics" }] }`

#### CM-8.5 (mobile prep) — FCM token registration
- Backend endpoint: `POST /auth/fcm-token` (body: `{ token: "..." }`)
- Stores FCM token per user for push notifications

---

### Phase 7: Profile & Polish

#### Step 7.1 — Profile Screen

**Files to create:**
- `lib/features/profile/data/profile_api.dart` — GET /auth/me wrapper
- `lib/features/profile/states/profile_state.dart` — Signals: current user profile
- `lib/features/profile/screens/profile_screen.dart` — display name, email, role, email verification status, logout button

#### Step 7.2 — Error & Loading States (CM-13.2)

Systematic pass across every screen:
- **Loading states:** Skeleton loaders for browse, detail, chat threads, messages
- **Empty states:** Illustrated empty states with action prompts
- **Error states:** Retry buttons, network vs server error distinction
- **Form validation:** Inline field errors from 422 responses mapped to form fields

---

## 5. Consistency Guidelines

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Signal variables | camelCase, descriptive noun | `listingsSignal`, `authStatus` |
| Computed signals | `Computed<T>` | `computed(() => ...)` |
| Screen files | `*_screen.dart` | `login_screen.dart` |
| Widget files | `*_widget.dart` or descriptive noun | `price_tag.dart` |
| Model files | Singular noun | `listing.dart`, `user.dart` |
| API files | `*_api.dart` | `listings_api.dart` |
| Repository files | `*_repository.dart` | `auth_repository.dart` |
| State files | `*_state.dart` | `listings_state.dart` |
| Route names | `RouteNames` class constants | `RouteNames.browse` |

### File Organization Rules

1. **Feature files never import from other features** — use `core/` for shared code
2. **Screens only import from their own feature + `core/`**
3. **Repositories depend on API + models, never on screens or states**
4. **States depend on repositories, never on screens**
5. **Models are pure Dart — no Flutter imports**

### ForUI Usage Rules

1. Always use `FTheme.of(context)` for theme data, never raw `Theme.of(context)`
2. Use ForUI components: `FButton`, `FCard`, `FForm`, `FTextField`, `FBadge`, `FTabs`, `FBottomNavigationBar`
3. ForUI's `FTheme` wraps the entire app — replace `MaterialApp` with `FApp`
4. Use `forui_assets` icons (Lucide) instead of Material icons

### Signals Usage Rules

1. Create signals at the top of state classes, not scattered in widgets
2. Use `Signal<T>` for mutable state, `Computed<T>` for derived values
3. Use `SignalWidget` or `watch(signal)` in widget build methods
4. Never mutate signals from inside `build()` — only in actions/callbacks
5. Clean up subscriptions when widgets are disposed

### API Mapping Convention

| Backend | Dart |
|---------|------|
| DTO names | Freezed model names (match exactly where possible) |
| snake_case JSON keys | camelCase (via `@JsonKey(name: '...')` or `fieldRename`) |
| UUID strings | `String` in Dart (no UUID type) |
| ISO 8601 timestamps | `DateTime` in Dart |
| Nullable fields | `Type?` in Dart |

---

## 6. Testing Strategy

### Unit Tests (target: every repository + state)

| Layer | What to test | How |
|-------|-------------|-----|
| Models | Freezed serialization roundtrips | `fromJson(toJson(model)) == model` |
| Repositories | Correct API calls, error handling, pagination | Mock Retrofit API interface |
| States | Signal updates on actions, computed derivations | Mock repositories |
| Utils | Pure function tests for formatters, validators | Direct assertion |

### Widget Tests (target: every screen)

- Use `test_app.dart` helper that wraps widgets in `FTheme` + mock providers
- Test key user flows: form submission, navigation, error display
- Mock signals for controlled state in tests

### Integration Tests (target: critical paths)

- Auth flow end-to-end (signup -> verify -> login -> browse)
- Listing creation with image upload
- Chat send/receive via mock WS

---

## 7. Build Phases Summary

| Phase | What | Depends On | Est. Effort |
|-------|------|-----------|-------------|
| **1** | Core infrastructure (config, theme, router, API, auth state, shared widgets) | Nothing | 2-3 days |
| **2** | Auth feature (models, API, screens) | Phase 1 | 1-2 days |
| **3** | Listings feature (browse, detail, create, edit) | Phase 1 + 2 | 2-3 days |
| **4** | Image upload flow | Phase 3 | 1 day |
| **5** | Chat feature (WS client, threads, messages) | Phase 1 + 2 + Backend Epics 8-9 | 3-4 days |
| **6** | Backend gaps (categories endpoint, FCM token) | — | 0.5 day |
| **7** | Profile, polish, error states | Phase 2 | 1-2 days |

### Critical Path

```
Phase 1 (Core) -> Phase 2 (Auth) -> Phase 3 (Listings) -> Phase 4 (Images)
                                      |
                               Phase 5 (Chat) — blocked on backend Epics 8-9
                                      |
                               Phase 7 (Polish)
```

### Parallelizable Work

- **Phase 6** (backend gaps) can be done in parallel with any mobile phase
- **Phase 7** (profile + polish) can start as soon as Phase 2 is done
- **Phase 5** (chat) can have its models + API prepared before backend is ready

---

## 8. Backend Dependencies for Mobile

| Mobile Phase | Backend Feature | Status |
|-------------|----------------|--------|
| Phase 2 (Auth) | Auth endpoints (signup, login, OTP, refresh, me) | Done |
| Phase 3 (Listings) | Listings CRUD + browse/search | Done |
| Phase 3 (Categories) | `GET /categories` | **Needs CM-4.9** |
| Phase 4 (Images) | Image presign/confirm/delete | Done |
| Phase 5 (Chat) | Chats REST + WebSocket | **Needs Epics 8-9** |
| Phase 5 (Chat Push) | FCM token registration | **Needs backend addendum** |

**Recommendation:** Start Phases 1-4 immediately (all backend APIs exist). Begin Phase 5 preparation (models, API stubs, WS client skeleton) while backend Epics 8-9 are being implemented.

---

## Appendix A: Route Configuration Detail

```dart
// lib/core/router/app_router.dart
final router = GoRouter(
  initialLocation: '/',
  refreshListenable: authStateRefreshNotifier,
  redirect: (context, state) {
    final isLoggedIn = authStatus.value == AuthStatus.authenticated;
    final isAuthRoute = ['/login', '/signup', '/verify-otp'].contains(state.matchedLocation);

    if (!isLoggedIn && !isAuthRoute) return '/login';
    if (isLoggedIn && isAuthRoute) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/verify-otp', builder: (_, __) => const VerifyOtpScreen()),
    ShellRoute(
      builder: (_, __, child) => AppScaffold(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const BrowseScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatThreadsScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
    GoRoute(path: '/listings/create', builder: (_, __) => const CreateListingScreen()),
    GoRoute(path: '/listings/:id', builder: (_, state) => ListingDetailScreen(id: state.pathParameters['id']!)),
    GoRoute(path: '/listings/:id/edit', builder: (_, state) => EditListingScreen(id: state.pathParameters['id']!)),
    GoRoute(path: '/chats/:id', builder: (_, state) => ChatDetailScreen(chatId: state.pathParameters['id']!)),
  ],
);
```

## Appendix B: ForUI Component Mapping

| UI Element | ForUI Component |
|-----------|----------------|
| Button | `FButton` |
| Card | `FCard` |
| Text Field | `FTextField` |
| Badge/Chip | `FBadge` |
| Tabs | `FTabs` |
| Bottom Nav | `FBottomNavigationBar` |
| Dialog | `FDialog` |
| Toast/Snackbar | `FToast` |
| Avatar | `FAvatar` |
| Divider | `FDivider` |
| Switch/Toggle | `FSwitch` |
| Slider | `FSlider` |
| Progress | `FCircularProgress` / `FLinearProgress` |
| Icons | `forui_assets` (Lucide icons) |

## Appendix C: Environment Variables for Mobile

```dart
// lib/core/config/env.dart
@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'API_BASE_URL')
  static const String apiBaseUrl = _Env.apiBaseUrl;

  @EnviedField(varName: 'WS_BASE_URL')
  static const String wsBaseUrl = _Env.wsBaseUrl;

  @EnviedField(varName: 'ENV')
  static const String env = _Env.env;
}
```

```bash
# .env (for envied code generation)
API_BASE_URL=https://uni-stash.com/api/v1
WS_BASE_URL=wss://uni-stash.com
ENV=dev
```
