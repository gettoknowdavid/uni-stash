# UniStash MVP — Phase 6 & 7 Implementation Guide

> **Date:** September 21, 2026
> **Status:** Ready for implementation
> **Scope:** Detailed pseudo-code for Phase 6 (Mobile Listings Flow) and Phase 7 (Mobile Chats Feature)
> **Prerequisites:** Phases 0–4 backend complete; Pusher Channels + Beams configured

---

## Table of Contents

- [Phase 6 — Mobile: Listings Flow Completion](#phase-6--mobile-listings-flow-completion)
  - [6.1 Data Layer: Chats API Client](#61-data-layer-chats-api-client)
  - [6.2 Data Layer: Sales API Client](#62-data-layer-sales-api-client)
  - [6.3 Data Layer: Chats Repository](#63-data-layer-chats-repository)
  - [6.4 Data Layer: Sales Repository](#64-data-layer-sales-repository)
  - [6.5 DI Wiring: Chats + Sales Registrations](#65-di-wiring-chats--sales-registrations)
  - [6.6 ReserveButton: Full Implementation](#66-reservebutton-full-implementation)
  - [6.7 Status-Driven Footer Actions](#67-status-driven-footer-actions)
  - [6.8 Chat With Seller Button](#68-chat-with-seller-button)
  - [6.9 My Purchases Screen](#69-my-purchases-screen)
  - [6.10 My Sales Screen](#610-my-sales-screen)
  - [6.11 Profile Page: Purchases/Sales Entry Points](#611-profile-page-purchasessales-entry-points)
  - [6.12 Report/Flag Entry Point](#612-reportflag-entry-point)
- [Phase 7 — Mobile: Chats Feature (New)](#phase-7--mobile-chats-feature-new)
  - [7.1 Models: ChatThread + ChatMessage](#71-models-chatthread--chatmessage)
  - [7.2 Data Layer: Chats Retrofit API](#72-data-layer-chats-retrofit-api)
  - [7.3 Data Layer: Chats Repository](#73-data-layer-chats-repository)
  - [7.4 Realtime Client: Pusher Channels](#74-realtime-client-pusher-channels)
  - [7.5 View Model: Chat Threads List](#75-view-model-chat-threads-list)
  - [7.6 View Model: Single Chat](#76-view-model-single-chat)
  - [7.7 Page: Chat Threads List (Bottom Nav)](#77-page-chat-threads-list-bottom-nav)
  - [7.8 Page: Real Chat Page](#78-page-real-chat-page)
  - [7.9 Push Notifications: Device Registration](#79-push-notifications-device-registration)
  - [7.10 Deep-Link from Push to Chat](#710-deep-link-from-push-to-chat)
- [File Tree Summary](#file-tree-summary)
- [Acceptance Criteria Checklist](#acceptance-criteria-checklist)

---

## Phase 6 — Mobile: Listings Flow Completion

Phase 6 transforms the listing detail page from a read-only view into a
fully interactive transaction surface. The buyer can reserve, chat, and
track purchases; the seller can manage status and mark items sold.

---

### 6.1 Data Layer: Chats API Client

Create the Retrofit API client for chats. This will be consumed by both
Phase 6 (the "Chat with seller" button) and Phase 7 (full chat feature).

```
FILE: lib/features/chats/data/chats_api.dart

// Retrofit API client for chat endpoints.
//
// Endpoints (from backend):
//   POST   /api/v1/chats                   — create/get chat for a listing
//   GET    /api/v1/chats                   — list user's chat threads
//   GET    /api/v1/chats/{id}/messages     — cursor-paginated messages
//   POST   /api/v1/chats/{id}/messages     — send a message
//   POST   /api/v1/chats/{id}/read         — mark messages as read

@RestApi()
abstract class ChatsApiClient {
  factory ChatsApiClient(Dio dio, {String? baseUrl}) = _ChatsApiClient;

  // Create or fetch existing chat thread for a listing.
  // Idempotent: calling twice for the same listing+buyer returns the same chat_id.
  @POST('/api/v1/chats')
  Future<ApiResponse<ChatCreatedResponse>> createChat(
    @Body() CreateChatRequest request,
  );

  // List the current user's chat threads (with unread counts).
  @GET('/api/v1/chats')
  Future<ApiResponse<ChatThreadsResponse>> listChats({
    @Query('limit') int? limit,
  });

  // Cursor-paginated message history for a chat.
  // Returns newest-first; client reverses for display.
  @GET('/api/v1/chats/{id}/messages')
  Future<ApiResponse<ChatMessagesResponse>> listMessages(
    @Path() String id, {
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  // Send a message (REST fallback; realtime is the primary path).
  @POST('/api/v1/chats/{id}/messages')
  Future<ApiResponse<ChatMessage>> sendMessage(
    @Path() String id,
    @Body() SendMessageRequest request,
  );

  // Mark all counterpart messages as read.
  @POST('/api/v1/chats/{id}/read')
  Future<ApiResponse<void>> markRead(@Path() String id);
}

// --- Request / Response DTOs (freezed) ---

// Request body for creating a chat.
@freezed
abstract class CreateChatRequest with _$CreateChatRequest {
  const factory CreateChatRequest({
    @JsonKey(name: 'listing_id') required String listingId,
  }) = _CreateChatRequest;

  factory CreateChatRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateChatRequestFromJson(json);
}

// Response from POST /chats — just the chat_id.
@freezed
abstract class ChatCreatedResponse with _$ChatCreatedResponse {
  const factory ChatCreatedResponse({
    @JsonKey(name: 'chat_id') required String chatId,
  }) = _ChatCreatedResponse;

  factory ChatCreatedResponse.fromJson(Map<String, dynamic> json) =>
      _$ChatCreatedResponseFromJson(json);
}

// Response from GET /chats — list of threads.
@freezed
abstract class ChatThreadsResponse with _$ChatThreadsResponse {
  const factory ChatThreadsResponse({
    required List<ChatThread> chats,
  }) = _ChatThreadsResponse;

  factory ChatThreadsResponse.fromJson(Map<String, dynamic> json) =>
      _$ChatThreadsResponseFromJson(json);
}

// Response from GET /chats/{id}/messages — paginated messages.
@freezed
abstract class ChatMessagesResponse with _$ChatMessagesResponse {
  const factory ChatMessagesResponse({
    required List<ChatMessage> messages,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _ChatMessagesResponse;

  factory ChatMessagesResponse.fromJson(Map<String, dynamic> json) =>
      _$ChatMessagesResponseFromJson(json);
}

// Request body for sending a message.
@freezed
abstract class SendMessageRequest with _$SendMessageRequest {
  const factory SendMessageRequest({
    required String body,
  }) = _SendMessageRequest;

  factory SendMessageRequest.fromJson(Map<String, dynamic> json) =>
      _$SendMessageRequestFromJson(json);
}
```

---

### 6.2 Data Layer: Sales API Client

```
FILE: lib/features/sales/data/sales_api.dart

// Retrofit API client for sale history endpoints.
//
// Endpoints:
//   GET /api/v1/sales/purchases  — items the current user bought
//   GET /api/v1/sales/mine       — items the current user sold

@RestApi()
abstract class SalesApiClient {
  factory SalesApiClient(Dio dio, {String? baseUrl}) = _SalesApiClient;

  @GET('/api/v1/sales/purchases')
  Future<ApiResponse<SalesListResponse>> myPurchases({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  @GET('/api/v1/sales/mine')
  Future<ApiResponse<SalesListResponse>> mySales({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });
}

@freezed
abstract class SalesListResponse with _$SalesListResponse {
  const factory SalesListResponse({
    required List<SaleRecord> sales,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _SalesListResponse;

  factory SalesListResponse.fromJson(Map<String, dynamic> json) =>
      _$SalesListResponseFromJson(json);
}
```

---

### 6.3 Data Layer: Chats Repository

```
FILE: lib/features/chats/data/chats_repository.dart

// Repository wrapping ChatsApiClient with Result-based error handling.
// Follows the same pattern as ListingsRepository.

abstract interface class ChatsRepository {
  /// Create or fetch an existing chat for a listing.
  Future<Result<String>> createChat(String listingId);

  /// List the current user's chat threads.
  Future<Result<List<ChatThread>>> listThreads({int limit});

  /// Fetch message history for a chat (newest first).
  Future<Result<ChatMessagesResponse>> listMessages(
    String chatId, {
    String? cursor,
    int limit,
  });

  /// Send a message in a chat.
  Future<Result<ChatMessage>> sendMessage(String chatId, String body);

  /// Mark all counterpart messages as read.
  Future<Result<void>> markRead(String chatId);
}

class ChatsRepositoryImpl implements ChatsRepository {
  ChatsRepositoryImpl(this._client, this._logger);

  final ChatsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<String>> createChat(String listingId) async {
    try {
      final response = await _client.createChat(
        CreateChatRequest(listingId: listingId),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.chatId);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] createChat failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] createChat unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<List<ChatThread>>> listThreads({int limit = 20}) async {
    try {
      final response = await _client.listChats(limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.chats);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] listThreads failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] listThreads unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ChatMessagesResponse>> listMessages(
    String chatId, {
    String? cursor,
    int limit = 30,
  }) async {
    try {
      final response = await _client.listMessages(
        chatId,
        cursor: cursor,
        limit: limit,
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] listMessages failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] listMessages unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ChatMessage>> sendMessage(String chatId, String body) async {
    try {
      final response = await _client.sendMessage(
        chatId,
        SendMessageRequest(body: body),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] sendMessage failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] sendMessage unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> markRead(String chatId) async {
    try {
      final response = await _client.markRead(chatId);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[ChatsRepository] markRead failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ChatsRepository] markRead unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
```

---

### 6.4 Data Layer: Sales Repository

```
FILE: lib/features/sales/data/sales_repository.dart

// Repository for sale history (My Purchases / My Sales).

abstract interface class SalesRepository {
  Future<Result<SalesListResponse>> myPurchases({String? cursor, int limit});
  Future<Result<SalesListResponse>> mySales({String? cursor, int limit});
}

class SalesRepositoryImpl implements SalesRepository {
  SalesRepositoryImpl(this._client, this._logger);

  final SalesApiClient _client;
  final Logger _logger;

  @override
  Future<Result<SalesListResponse>> myPurchases({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _client.myPurchases(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SalesRepository] myPurchases failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SalesRepository] myPurchases unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<SalesListResponse>> mySales({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _client.mySales(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SalesRepository] mySales failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SalesRepository] mySales unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
```

---

### 6.5 DI Wiring: Chats + Sales Registrations

```
FILE: lib/core/config/di.dart

// Add to _registerListings() or create new _registerChats()/_registerSales():

void _registerChats() {
  di.registerSingletonWithDependencies<ChatsApiClient>(
    () => ChatsApiClient(di<Dio>()),
    dependsOn: [Dio],
  );

  di.registerSingletonWithDependencies<ChatsRepository>(
    () => ChatsRepositoryImpl(di<ChatsApiClient>(), di<Logger>()),
    dependsOn: [ChatsApiClient],
  );
}

void _registerSales() {
  di.registerSingletonWithDependencies<SalesApiClient>(
    () => SalesApiClient(di<Dio>()),
    dependsOn: [Dio],
  );

  di.registerSingletonWithDependencies<SalesRepository>(
    () => SalesRepositoryImpl(di<SalesApiClient>(), di<Logger>()),
    dependsOn: [SalesApiClient],
  );
}

// Call both from configureAuthenticatedScope():
void configureAuthenticatedScope() {
  if (di.hasScope(Scope.authenticated)) return;
  di.pushNewScope(scopeName: Scope.authenticated);
  _registerListings();
  _registerImages();
  _registerSchools();
  _registerProfile();
  _registerChats();    // NEW
  _registerSales();    // NEW
}
```

---

### 6.6 ReserveButton: Full Implementation

The current `_ReserveButton` is a dead placeholder. This replaces it with
a fully wired widget that reacts to listing status.

```
FILE: lib/features/listings/pages/listing_detail_page.dart

// REPLACE the existing _ReserveButton class with:

class _ReserveButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalBuilder(
      builder: (context) {
        final model = di<ListingDetailViewModel>();
        final detail = model.detail.value;
        final currentUserId = di<UserViewModel>().currentUser.value?.id;
        final isMe = currentUserId == detail?.seller.id;

        // Seller never sees the footer button.
        if (isMe || detail == null) return const SizedBox.shrink();

        // --- Status-driven footer ---
        return ShadDecorator(
          decoration: ShadDecoration(
            border: ShadBorder(
              top: ShadBorderSide(color: theme.colorScheme.border),
            ),
          ),
          child: Padding(
            padding: const .all(16),
            child: switch (detail.status) {
              // ACTIVE: show RESERVE button
              ListingStatus.active => ShadButton(
                width: double.infinity,
                onPressed: () => _handleReserve(context, detail.id),
                child: const Text('RESERVE'),
              ),

              // RESERVED by me: show "Awaiting meetup" + Unreserve
              ListingStatus.reserved when detail.reservedBy == currentUserId =>
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Awaiting meetup',
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton.outline(
                            onPressed: () =>
                                _handleUnreserve(context, detail.id),
                            child: const Text('UNRESERVE'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              // RESERVED by someone else: show "Reserved by another buyer"
              ListingStatus.reserved => ShadButton(
                width: double.infinity,
                enabled: false,
                child: const Text('RESERVED'),
              ),

              // SOLD: show "Sold" (disabled)
              ListingStatus.sold => ShadButton(
                width: double.infinity,
                enabled: false,
                child: const Text('SOLD'),
              ),

              // DELETED / fallback: don't show anything
              _ => const SizedBox.shrink(),
            },
          ),
        );
      },
    );
  }

  // Handle reserve with 409 conflict retry + email verification prompt.
  Future<void> _handleReserve(BuildContext context, String listingId) async {
    final model = di<ListingDetailViewModel>();
    final result = await _repository.reserve(listingId);

    switch (result) {
      case Success():
        // Refresh the detail view to show updated status.
        model.fetch(listingId);
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast(
              title: const Text('Reserved'),
              description: const Text(
                'You reserved this item. Chat with the seller to arrange a meetup.',
              ),
            ),
          );
        }

      case Failure(:final message, :final code):
        // Email not verified → prompt verification.
        if (code == 'email_not_verified') {
          if (context.mounted) {
            _showEmailVerificationPrompt(context);
          }
          return;
        }

        // 409 Conflict → listing was taken; refresh and toast.
        if (message.toLowerCase().contains('no longer available')) {
          model.fetch(listingId);
          if (context.mounted) {
            ShadToaster.of(context).show(
              ShadToast.destructive(
                title: const Text('Unavailable'),
                description: const Text(
                  'This item is no longer available.',
                ),
              ),
            );
          }
          return;
        }

        // Other errors → toast.
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Reserve Failed'),
              description: Text(message),
            ),
          );
        }
    }
  }

  Future<void> _handleUnreserve(BuildContext context, String listingId) async {
    final model = di<ListingDetailViewModel>();
    final result = await model.unreserve(listingId);

    switch (result) {
      case Success():
        model.fetch(listingId);
        if (context.mounted) {
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('Unreserved'),
              description: Text('This item is available again.'),
            ),
          );
        }
      case Failure(:final message):
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Failed'),
              description: Text(message),
            ),
          );
        }
    }
  }

  void _showEmailVerificationPrompt(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Verify Your Email'),
        description: const Text(
          'You need to verify your email before you can reserve items.',
        ),
        actions: [
          ShadButton(
            onPressed: () {
              ctx.pop();
              context.push(UsRoutes.verify);
            },
            child: const Text('VERIFY'),
          ),
        ],
      ),
    );
  }
}
```

---

### 6.7 Status-Driven Footer Actions

The seller's footer is different from the buyer's. This adds a
`_SellerFooter` widget that replaces the single `_ReserveButton` when
the current user is the listing owner.

```
FILE: lib/features/listings/pages/listing_detail_page.dart

// In _ListingDetailView.build(), replace:
//   footer: isMe ? null : const _ReserveButton(),
// with:
//   footer: isMe ? _SellerFooter(id: id) : const _ReserveButton(),

class _SellerFooter extends StatelessWidget {
  const _SellerFooter({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalBuilder(
      builder: (context) {
        final detail = di<ListingDetailViewModel>().detail.value;
        if (detail == null) return const SizedBox.shrink();

        return ShadDecorator(
          decoration: ShadDecoration(
            border: ShadBorder(
              top: ShadBorderSide(color: theme.colorScheme.border),
            ),
          ),
          child: Padding(
            padding: const .all(16),
            child: switch (detail.status) {
              // ACTIVE by seller: no action needed (listing is live).
              ListingStatus.active => const SizedBox.shrink(),

              // RESERVED: show Mark as Sold + Unreserve buttons.
              ListingStatus.reserved => Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: () => _handleUnreserve(context),
                      child: const Text('UNRESERVE'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadButton(
                      onPressed: () => _handleMarkSold(context),
                      child: const Text('MARK AS SOLD'),
                    ),
                  ),
                ],
              ),

              // SOLD: no action (already sold).
              ListingStatus.sold => const SizedBox.shrink(),

              // DELETED / fallback: no action.
              _ => const SizedBox.shrink(),
            },
          ),
        );
      },
    );
  }

  Future<void> _handleMarkSold(BuildContext context) async {
    final model = di<ListingDetailViewModel>();

    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('MARK AS SOLD?'),
        description: const Text(
          'This will mark the listing as sold and record the sale. '
          'This action cannot be undone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => ctx.pop(false),
            child: const Text('CANCEL'),
          ),
          ShadButton(
            onPressed: () => ctx.pop(true),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await model.markAsSold(id);
    switch (result) {
      case Success():
        model.fetch(id);
        if (context.mounted) {
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('Sold'),
              description: Text('Listing marked as sold.'),
            ),
          );
        }
      case Failure(:final message):
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Failed'),
              description: Text(message),
            ),
          );
        }
    }
  }

  Future<void> _handleUnreserve(BuildContext context) async {
    final model = di<ListingDetailViewModel>();
    final result = await model.unreserve(id);
    switch (result) {
      case Success():
        model.fetch(id);
      case Failure(:final message):
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Failed'),
              description: Text(message),
            ),
          );
        }
    }
  }
}
```

---

### 6.8 Chat With Seller Button

Add a "Chat with seller" button visible to non-owner buyers when the
listing is active or reserved. This creates (or fetches) a chat thread
and navigates to it.

```
FILE: lib/features/listings/pages/listing_detail_page.dart

// In _ListingDetailView.build(), after the status section and before
// the _SellerDetails section, add:

// --- Chat with seller button (non-owner only) ---
if (!isMe && detail.status != ListingStatus.deleted) ...[
  const SizedBox(height: 24),
  Padding(
    padding: const .symmetric(horizontal: 16),
    child: ShadButton(
      width: double.infinity,
      variant: ShadButtonVariant.outline,
      onPressed: () => _handleChatWithSeller(context, detail),
      child: const Text('CHAT WITH SELLER'),
    ),
  ),
],

// --- Handler (as a method or top-level function) ---

Future<void> _handleChatWithSeller(
  BuildContext context,
  ListingDetailResponse detail,
) async {
  final chatsRepo = di<ChatsRepository>();

  // Show a loading indicator while creating/fetching the chat.
  if (context.mounted) {
    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: ShadSpinner()),
    );
  }

  final result = await chatsRepo.createChat(detail.id);

  // Dismiss the loading dialog.
  if (context.mounted) {
    context.pop(); // dismiss loading dialog
  }

  switch (result) {
    case Success(:final value):
      // Navigate to the chat page with the chat_id.
      if (context.mounted) {
        context.push(
          '${UsRoutes.chat}/$value',
          extra: {
            'chatId': value,
            'counterpartName': detail.seller.displayName,
            'listingTitle': detail.title,
          },
        );
      }

    case Failure(:final message):
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Chat Failed'),
            description: Text(message),
          ),
        );
      }
  }
}
```

---

### 6.9 My Purchases Screen

```
FILE: lib/features/sales/pages/my_purchases_page.dart

// A page showing items the current user has bought.
// Uses cursor pagination with infinite scroll.

class MyPurchasesPage extends StatefulWidget {
  const MyPurchasesPage({super.key});

  @override
  State<MyPurchasesPage> createState() => _MyPurchasesPageState();
}

class _MyPurchasesPageState extends State<MyPurchasesPage> {
  late final SalesRepository _salesRepo;
  final List<SaleRecord> _sales = [];
  String? _nextCursor;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _salesRepo = di<SalesRepository>();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final result = await _salesRepo.myPurchases(cursor: _nextCursor);

    switch (result) {
      case Success(:final value):
        setState(() {
          _sales.addAll(value.sales);
          _nextCursor = value.nextCursor;
          _hasMore = value.nextCursor != null;
          _isLoading = false;
        });
      case Failure():
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return UsPage(
      header: const UsPageHeader(title: Text('MY PURCHASES')),
      body: _sales.isEmpty && _isLoading
          ? const Center(child: ShadSpinner())
          : _sales.isEmpty
              ? Center(
                  child: Text(
                    'No purchases yet',
                    style: theme.textTheme.muted,
                  ),
                )
              : ListView.builder(
                  itemCount: _sales.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _sales.length) {
                      _loadMore(); // trigger next page load
                      return const Center(child: ShadSpinner());
                    }
                    return _SaleTile(sale: _sales[index]);
                  },
                ),
    );
  }
}

// Shared tile widget for both purchases and sales.
class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});
  final SaleRecord sale;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final date = timeago.format(sale.createdAt);

    return ListTile(
      title: Text(
        sale.listingTitle,
        style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        sale.price != null ? '${sale.price} • $date' : 'Barter • $date',
        style: theme.textTheme.muted,
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: theme.colorScheme.mutedForeground,
      ),
      onTap: () {
        context.push(UsRoutes.listingDetailsRoute(sale.listingId));
      },
    );
  }
}
```

---

### 6.10 My Sales Screen

Mirrors My Purchases but calls `mySales` instead.

```
FILE: lib/features/sales/pages/my_sales_page.dart

// Identical structure to MyPurchasesPage but calls:
//   _salesRepo.mySales(cursor: _nextCursor)
//
// Reuses the same _SaleTile widget.

class MySalesPage extends StatefulWidget {
  const MySalesPage({super.key});

  @override
  State<MySalesPage> createState() => _MySalesPageState();
}

class _MySalesPageState extends State<MySalesPage> {
  // Same pattern as MyPurchasesPage:
  // - _salesRepo.mySales(cursor: _nextCursor)
  // - ListView.builder with infinite scroll
  // - _SaleTile for each item
  // - Empty state: "No sales yet"
}
```

---

### 6.11 Profile Page: Purchases/Sales Entry Points

Add two navigation items to the profile page that link to the new screens.

```
FILE: lib/features/profile/pages/profile_page.dart

// In the profile page body, add a section after the stats:

// --- Sales History Section ---
const SizedBox(height: 24),
Padding(
  padding: const .symmetric(horizontal: 16),
  child: Text('SALES HISTORY', style: theme.textTheme.labelSm),
),
const SizedBox(height: 8),

// My Purchases tile
ListTile(
  leading: Icon(LucideIcons.shoppingBag, color: theme.colorScheme.primary),
  title: const Text('My Purchases'),
  trailing: Icon(LucideIcons.chevronRight, color: theme.colorScheme.mutedForeground),
  onTap: () => context.push('/sales/purchases'),
),

// My Sales tile
ListTile(
  leading: Icon(LucideIcons.store, color: theme.colorScheme.primary),
  title: const Text('My Sales'),
  trailing: Icon(LucideIcons.chevronRight, color: theme.colorScheme.mutedForeground),
  onTap: () => context.push('/sales/mine'),
),

// Register routes in us_router.dart:
// GoRoute(
//   path: '/sales/purchases',
//   builder: (context, state) => const MyPurchasesPage(),
// ),
// GoRoute(
//   path: '/sales/mine',
//   builder: (context, state) => const MySalesPage(),
// ),
```

---

### 6.12 Report/Flag Entry Point

Add a "Report" option to the listing detail page for non-owners.

```
FILE: lib/features/listings/pages/listing_detail_page.dart

// In the seller details section, add a text button:

if (!isMe) ...[
  const SizedBox(height: 16),
  Center(
    child: TextButton(
      onPressed: () => _showReportSheet(context, detail),
      child: Text(
        'Report this listing',
        style: theme.textTheme.muted.copyWith(
          color: theme.colorScheme.destructive,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  ),
],

// --- Report sheet (Phase 8 will expand this) ---

void _showReportSheet(BuildContext context, ListingDetailResponse detail) {
  showShadDialog(
    context: context,
    builder: (ctx) => ShadDialog(
      title: const Text('REPORT LISTING'),
      children: [
        Text(
          'Why are you reporting this listing?',
          style: ShadTheme.of(ctx).textTheme.p,
        ),
        const SizedBox(height: 16),
        // Simple text field for reason
        // On submit: POST /api/v1/reports with { listing_id, reason }
        // For now, just show a placeholder toast.
        ShadButton(
          onPressed: () {
            ctx.pop();
            ShadToaster.of(context).show(
              const ShadToast(
                title: Text('Reported'),
                description: Text('Thank you. We will review this listing.'),
              ),
            );
          },
          child: const Text('SUBMIT'),
        ),
      ],
    ),
  );
}
```

---

## Phase 7 — Mobile: Chats Feature (New)

Phase 7 builds the complete in-app chat experience: a thread list with
unread badges, a real-time chat page with Pusher Channels, and push
notification registration.

---

### 7.1 Models: ChatThread + ChatMessage

```
FILE: lib/features/chats/models/chat_models.dart

// Freezed models for chat data. These match the backend's wire format.

@freezed
abstract class ChatThread with _$ChatThread {
  const factory ChatThread({
    required String id,
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'listing_title') required String listingTitle,
    @JsonKey(name: 'counterpart_id') required String counterpartId,
    @JsonKey(name: 'counterpart_name') required String counterpartName,
    @JsonKey(name: 'counterpart_photo_url') String? counterpartPhotoUrl,
    @JsonKey(name: 'last_message_preview') String? lastMessagePreview,
    @JsonKey(name: 'last_message_at') DateTime? lastMessageAt,
    @JsonKey(name: 'unread_count') @Default(0) int unreadCount,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ChatThread;

  factory ChatThread.fromJson(Map<String, dynamic> json) =>
      _$ChatThreadFromJson(json);
}

@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'sender_id') required String senderId,
    required String body,
    @JsonKey(name: 'read_at') DateTime? readAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
```

---

### 7.2 Data Layer: Chats Retrofit API

Already defined in 6.1. The same `ChatsApiClient` serves both phases.
Run `build_runner` after creating the freezed models:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

### 7.3 Data Layer: Chats Repository

Already defined in 6.3. The same `ChatsRepositoryImpl` serves both phases.

---

### 7.4 Realtime Client: Pusher Channels

This is the key Phase 7 component. The realtime client connects to
Pusher Channels, subscribes to the chat's private channel, and emits
events that the chat view model listens to.

```
FILE: lib/features/chats/data/realtime_client.dart

// Pusher Channels client for real-time chat events.
//
// This is the ONLY file that imports Pusher-specific packages.
// The rest of the app talks to RealtimeClient through a plain Dart
// interface, so swapping Pusher for another provider means changing
// only this file.
//
// Dependencies: web_socket_channel (already in pubspec.yaml)
// No native Pusher SDK needed — we use the WebSocket protocol directly.

class RealtimeClient {
  RealtimeClient({required this.baseUrl, required this.authEndpoint});

  /// The Pusher WebSocket endpoint (e.g. "wss://ws-eu.pusher.com").
  final String baseUrl;

  /// The backend auth endpoint for private channels.
  /// POST to this with { socket_id, channel_name } to get the auth response.
  final String authEndpoint;

  WebSocketChannel? _channel;
  String? _socketId;
  final Map<String, List<Function(Map<String, dynamic>)>> _listeners = {};
  bool _isConnected = false;

  /// Whether the client is currently connected to Pusher.
  bool get isConnected => _isConnected;

  /// Connect to Pusher and wait for the connection_established event.
  Future<void> connect() async {
    // Pusher WebSocket protocol:
    // 1. Open WebSocket to wss://ws-{cluster}.pusher.com/app/{key}
    // 2. Receive connection_established event with socket_id
    // 3. Use socket_id to authenticate private channel subscriptions

    final url = '$baseUrl/app/{PUSHER_KEY}';
    // NOTE: PUSHER_KEY is injected from Config at runtime.

    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen(
      (data) {
        final event = _parseEvent(data);
        if (event != null) {
          _handleEvent(event);
        }
      },
      onDone: () {
        _isConnected = false;
        _attemptReconnect(); // auto-reconnect with backoff
      },
      onError: (error) {
        _isConnected = false;
      },
    );
  }

  /// Subscribe to a private chat channel.
  /// Authenticates with the backend before subscribing.
  Future<void> subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic> data) onNewMessage,
    required void Function(Map<String, dynamic> data) onReadReceipt,
  }) async {
    final channelName = 'private-chat-$chatId';

    // Register listeners.
    _listeners.putIfAbsent(channelName, () => []);
    _listeners[channelName]!.add((event) {
      switch (event['event']) {
        case 'message.new':
          onNewMessage(event['data'] as Map<String, dynamic>);
        case 'message.read':
          onReadReceipt(event['data'] as Map<String, dynamic>);
      }
    });

    // Authenticate with backend for this private channel.
    final authResponse = await _authenticateChannel(channelName);
    if (authResponse == null) return;

    // Send subscribe event to Pusher.
    _sendEvent({
      'event': 'pusher:subscribe',
      'data': {
        'channel': channelName,
        'auth': authResponse['auth'],
      },
    });
  }

  /// Unsubscribe from a channel.
  void unsubscribeFromChat(String chatId) {
    final channelName = 'private-chat-$chatId';
    _listeners.remove(channelName);
    _sendEvent({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channelName},
    });
  }

  /// Disconnect from Pusher.
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _listeners.clear();
  }

  // --- Internal helpers ---

  /// Call the backend's /api/v1/realtime/auth endpoint.
  Future<Map<String, dynamic>?> _authenticateChannel(String channelName) async {
    // Uses the same Dio instance (with auth interceptor) to POST:
    //   POST /api/v1/realtime/auth
    //   Body: { "socket_id": _socketId, "channel_name": channelName }
    // Returns: { "auth": "{key}:{signature}" }
    //
    // Implementation uses Dio (injected via constructor or from di).
    // Error handling: return null on failure (log + degrade to REST).
  }

  void _handleEvent(Map<String, dynamic> event) {
    final channel = event['channel'] as String?;
    if (channel == null) return;

    final listeners = _listeners[channel];
    if (listeners != null) {
      for (final listener in listeners) {
        listener(event);
      }
    }
  }

  Map<String, dynamic>? _parseEvent(dynamic data) {
    try {
      return jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _sendEvent(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  void _attemptReconnect() {
    // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isConnected) connect();
    });
  }
}
```

---

### 7.5 View Model: Chat Threads List

```
FILE: lib/features/chats/view_models/chat_threads_view_model.dart

// View model for the chat threads list (bottom nav "Chat" tab).
// Manages the list of threads and unread count for the badge.

class ChatThreadsViewModel implements Disposable {
  ChatThreadsViewModel(this._repository) {
    _init();
  }

  final ChatsRepository _repository;

  final Signal<List<ChatThread>> threads = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  /// Total unread count across all threads (for the badge dot).
  Signal<int> get unreadCount => computed(() =>
      threads.value.fold(0, (sum, t) => sum + t.unreadCount));

  late final void Function() fetch;

  void _init() {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;

      final result = await _repository.listThreads();
      switch (result) {
        case Success(:final value):
          threads.value = value;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });
  }

  /// Called when a new message arrives via realtime.
  /// Updates the thread's last message preview and unread count.
  void onNewMessage(String chatId, String preview) {
    final current = threads.value.toList();
    final index = current.indexWhere((t) => t.id == chatId);
    if (index == -1) return;

    final thread = current[index];
    current.removeAt(index);
    current.insert(
      0,
      thread.copyWith(
        lastMessagePreview: preview,
        lastMessageAt: DateTime.now(),
        unreadCount: thread.unreadCount + 1,
      ),
    );
    threads.value = current;
  }

  /// Reset unread count for a thread (when user opens it).
  void markThreadRead(String chatId) {
    final current = threads.value.toList();
    final index = current.indexWhere((t) => t.id == chatId);
    if (index == -1) return;

    current[index] = current[index].copyWith(unreadCount: 0);
    threads.value = current;
  }

  void dispose() {
    threads.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() => dispose();
}
```

---

### 7.6 View Model: Single Chat

```
FILE: lib/features/chats/view_models/chat_view_model.dart

// View model for a single chat conversation.
// Manages message list, sending, pagination, and realtime events.

class ChatViewModel implements Disposable {
  ChatViewModel(
    this._repository,
    this._realtimeClient, {
    required this.chatId,
    required this.currentUserId,
  }) {
    _init();
  }

  final ChatsRepository _repository;
  final RealtimeClient _realtimeClient;
  final String chatId;
  final String currentUserId;

  final Signal<List<ChatMessage>> messages = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isSending = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> isConnected = signal(false);

  String? _nextCursor;
  bool _hasMore = true;

  late final void Function() loadMessages;
  late final Future<void> Function(String body) sendMessage;

  void _init() {
    loadMessages = action0(() async {
      isLoading.value = true;
      error.value = null;

      final result = await _repository.listMessages(chatId);
      switch (result) {
        case Success(:final value):
          // Backend returns newest-first; reverse for display (oldest at top).
          messages.value = value.messages.reversed.toList();
          _nextCursor = value.nextCursor;
          _hasMore = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;

      // Subscribe to realtime events after loading.
      _subscribeToRealtime();
    });

    sendMessage = (String body) async {
      if (body.trim().isEmpty) return;
      isSending.value = true;

      final result = await _repository.sendMessage(chatId, body.trim());
      switch (result) {
        case Success(:final value):
          // Optimistically add the sent message to the list.
          final current = messages.value.toList();
          // Avoid duplicate if realtime already delivered it.
          if (!current.any((m) => m.id == value.id)) {
            current.add(value);
            messages.value = current;
          }
        case Failure(:final message):
          error.value = message;
      }

      isSending.value = false;
    };
  }

  void _subscribeToRealtime() {
    _realtimeClient.subscribeToChat(
      chatId,
      onNewMessage: (data) {
        // Parse the event data and add the message to the list.
        final message = ChatMessage.fromJson(data);
        final current = messages.value.toList();
        // Deduplicate: don't add if we already have this message
        // (e.g., from optimistic local add in sendMessage).
        if (!current.any((m) => m.id == message.id)) {
          current.add(message);
          messages.value = current;
        }
      },
      onReadReceipt: (data) {
        // Update read status for messages sent by the current user.
        final lastReadId = data['last_read_message_id'] as String?;
        if (lastReadId == null) return;

        final current = messages.value.toList();
        for (var i = 0; i < current.length; i++) {
          if (current[i].senderId == currentUserId &&
              current[i].readAt == null) {
            current[i] = current[i].copyWith(readAt: DateTime.now());
          }
        }
        messages.value = current;
      },
    );
  }

  /// Load older messages (pull up / scroll to top).
  Future<void> loadMore() async {
    if (!_hasMore || isLoading.value) return;

    final result = await _repository.listMessages(
      chatId,
      cursor: _nextCursor,
    );

    switch (result) {
      case Success(:final value):
        final current = messages.value.toList();
        // Prepend older messages (reverse because backend returns newest-first).
        final older = value.messages.reversed.toList();
        current.insertAll(0, older);
        messages.value = current;
        _nextCursor = value.nextCursor;
        _hasMore = value.nextCursor != null;
      case Failure():
        break;
    }
  }

  /// Mark messages as read when the user opens/scrolls to bottom.
  Future<void> markRead() async {
    await _repository.markRead(chatId);
  }

  void dispose() {
    _realtimeClient.unsubscribeFromChat(chatId);
    messages.dispose();
    isLoading.dispose();
    isSending.dispose();
    error.dispose();
    isConnected.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() => dispose();
}
```

---

### 7.7 Page: Chat Threads List (Bottom Nav)

Replace the placeholder `ChatPage` with a real thread list.

```
FILE: lib/features/chats/pages/chat_page.dart

// REPLACE the entire placeholder ChatPage with:

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'chatThreads',
      init: (getIt) {
        getIt.registerLazySingletonAsync<ChatThreadsViewModel>(
          () async => ChatThreadsViewModel(di<ChatsRepository>()),
          onCreated: (model) async => model.fetch(),
          dispose: (vm) => vm.dispose(),
        );
      },
    );
  }

  @override
  void dispose() {
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('CHATS')),
      body: FutureBuilder<void>(
        future: di.isReady<ChatThreadsViewModel>(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != .done) {
            return const Center(child: ShadSpinner());
          }
          return const _ChatThreadsList();
        },
      ),
    );
  }
}

class _ChatThreadsList extends StatelessWidget {
  const _ChatThreadsList();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalBuilder(
      builder: (context) {
        final model = di<ChatThreadsViewModel>();
        final threads = model.threads.value;
        final isLoading = model.isLoading.value;
        final error = model.error.value;

        if (isLoading && threads.isEmpty) {
          return const Center(child: ShadSpinner());
        }

        if (error != null && threads.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error, style: theme.textTheme.muted),
                const SizedBox(height: 12),
                ShadButton.outline(
                  onPressed: model.fetch,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (threads.isEmpty) {
          return Center(
            child: Text(
              'No conversations yet',
              style: theme.textTheme.muted,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => model.fetch(),
          child: ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, _) => ShadSeparator.horizontal(
              margin: const .symmetric(horizontal: 16),
              color: theme.colorScheme.border,
            ),
            itemBuilder: (context, index) {
              final thread = threads[index];
              return _ChatThreadTile(thread: thread);
            },
          ),
        );
      },
    );
  }
}

class _ChatThreadTile extends StatelessWidget {
  const _ChatThreadTile({required this.thread});
  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasUnread = thread.unreadCount > 0;

    return ListTile(
      leading: UsAvatar(
        name: thread.counterpartName,
        photoUrl: thread.counterpartPhotoUrl,
        size: 44,
      ),
      title: Text(
        thread.listingTitle,
        style: theme.textTheme.p.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        thread.lastMessagePreview ?? 'No messages yet',
        style: theme.textTheme.muted.copyWith(
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (thread.lastMessageAt != null)
            Text(
              _formatTime(thread.lastMessageAt!),
              style: theme.textTheme.labelSm.copyWith(
                color: hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        // Mark as read locally.
        di<ChatThreadsViewModel>().markThreadRead(thread.id);
        // Navigate to the chat page.
        context.push(
          '${UsRoutes.chat}/${thread.id}',
          extra: {
            'chatId': thread.id,
            'counterpartName': thread.counterpartName,
            'listingTitle': thread.listingTitle,
          },
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}
```

---

### 7.8 Page: Real Chat Page

```
FILE: lib/features/chats/pages/chat_detail_page.dart

// The real chat page with message bubbles, input field, and connection indicator.
// Replaces the placeholder.

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({
    required this.chatId,
    required this.counterpartName,
    required this.listingTitle,
    super.key,
  });

  final String chatId;
  final String counterpartName;
  final String listingTitle;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  String? _scopeName;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'chat-${widget.chatId}',
      init: (getIt) {
        getIt.registerLazySingletonAsync<ChatViewModel>(
          () async => ChatViewModel(
            di<ChatsRepository>(),
            di<RealtimeClient>(),
            chatId: widget.chatId,
            currentUserId: di<UserViewModel>().currentUser.value!.id,
          ),
          onCreated: (model) async => model.loadMessages(),
          dispose: (vm) => vm.dispose(),
        );
      },
    );

    // Listen for scroll-to-top to load more messages.
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 0) {
      di<ChatViewModel>().loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final currentUserId = di<UserViewModel>().currentUser.value!.id;

    return UsPage(
      header: UsPageHeader(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.counterpartName),
            Text(
              widget.listingTitle,
              style: theme.textTheme.labelSm.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<void>(
        future: di.isReady<ChatViewModel>(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != .done) {
            return const Center(child: ShadSpinner());
          }
          return _ChatBody(
            currentUserId: currentUserId,
            scrollController: _scrollController,
          );
        },
      ),
      footer: _ChatInputBar(
        controller: _inputController,
        onSend: () {
          final text = _inputController.text.trim();
          if (text.isEmpty) return;
          di<ChatViewModel>().sendMessage(text);
          _inputController.clear();
        },
      ),
    );
  }
}

// --- Message list ---

class _ChatBody extends StatelessWidget {
  const _ChatBody({
    required this.currentUserId,
    required this.scrollController,
  });

  final String currentUserId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final model = di<ChatViewModel>();
        final messages = model.messages.value;
        final isLoading = model.isLoading.value;

        if (isLoading && messages.isEmpty) {
          return const Center(child: ShadSpinner());
        }

        if (messages.isEmpty) {
          return const Center(child: Text('Send a message to start chatting'));
        }

        return ListView.builder(
          controller: scrollController,
          reverse: false, // oldest at top, newest at bottom
          padding: const .all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == currentUserId;
            return _MessageBubble(
              message: message,
              isMe: isMe,
            );
          },
        );
      },
    );
  }
}

// --- Single message bubble ---

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const .only(bottom: 8),
        padding: const .symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary
              : theme.colorScheme.muted,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.body,
              style: theme.textTheme.p.copyWith(
                color: isMe
                    ? theme.colorScheme.primaryForeground
                    : theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: theme.textTheme.labelSm.copyWith(
                    color: isMe
                        ? theme.colorScheme.primaryForeground
                            .withOpacity(0.6)
                        : theme.colorScheme.mutedForeground,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt != null
                        ? LucideIcons.checkCheck
                        : LucideIcons.check,
                    size: 12,
                    color: message.readAt != null
                        ? theme.colorScheme.primaryForeground
                        : theme.colorScheme.primaryForeground
                            .withOpacity(0.6),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

// --- Input bar ---

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadDecorator(
      decoration: ShadDecoration(
        border: ShadBorder(
          top: ShadBorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const .symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onSend,
                icon: Icon(
                  LucideIcons.send,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

### 7.9 Push Notifications: Device Registration

Register the device's push token with the backend after login.

```
FILE: lib/features/notifications/data/notifications_api.dart

@RestApi()
abstract class NotificationsApiClient {
  factory NotificationsApiClient(Dio dio, {String? baseUrl}) =
      _NotificationsApiClient;

  @POST('/api/v1/notifications/register-device')
  Future<ApiResponse<void>> registerDevice(
    @Body() RegisterDeviceRequest request,
  );
}

@freezed
abstract class RegisterDeviceRequest with _$RegisterDeviceRequest {
  const factory RegisterDeviceRequest({
    required String token,
    required String platform,
  }) = _RegisterDeviceRequest;

  factory RegisterDeviceRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterDeviceRequestFromJson(json);
}
```

```
FILE: lib/features/notifications/data/notifications_repository.dart

// Fire-and-forget device registration. Called once after login.

class NotificationsRepository {
  NotificationsRepository(this._client, this._logger);

  final NotificationsApiClient _client;
  final Logger _logger;

  Future<void> registerDevice(String token, String platform) async {
    try {
      await _client.registerDevice(
        RegisterDeviceRequest(token: token, platform: platform),
      );
    } catch (e) {
      // Best-effort: don't block login if registration fails.
      _logger.w('[Notifications] Device registration failed', error: e);
    }
  }
}
```

```
FILE: lib/features/auth/view_models/auth_view_model.dart

// After successful login, register the device token.

// In the authenticate() method, after storing credentials:

// --- Push notification device registration (fire-and-forget) ---
Future<void> _registerPushDevice() async {
  try {
    // For web: use the Beams web SDK or skip.
    // For iOS/Android: get the APNs/FCM token from the OS.
    //
    // On web, Pusher Beams has a JS SDK that manages the service worker.
    // On mobile, use firebase_messaging or similar to get the token.
    //
    // For now, this is a placeholder that will be wired when native
    // push is configured. The backend endpoint is ready.
    //
    // final token = await PushNotifications.getToken();
    // final platform = Platform.isIOS ? 'ios' : 'android';
    // await di<NotificationsRepository>().registerDevice(token, platform);
  } catch (e) {
    // Silently fail — push registration is best-effort.
  }
}
```

---

### 7.10 Deep-Link from Push to Chat

When a push notification arrives while the app is in the foreground,
parse the data payload and navigate to the relevant chat.

```
FILE: lib/main.dart or lib/core/notifications/push_handler.dart

// Handle foreground push notifications.
// Called from the push notification listener setup.

void handleForegroundPush(Map<String, dynamic> data) {
  final chatId = data['chat_id'] as String?;
  if (chatId == null) return;

  // Navigate to the chat page.
  // This uses the navigator key from GoRouter.
  routerConfig.push(
    '${UsRoutes.chat}/$chatId',
    extra: {
      'chatId': chatId,
      'counterpartName': data['sender_name'] ?? 'Unknown',
      'listingTitle': data['listing_title'] ?? '',
    },
  );
}

// Setup (in main.dart or app initialization):
//
// Pusher Beams SDK initialization:
//   await PushNotifications.start();
//   PushNotifications.onMessageReceived((message) {
//     handleForegroundPush(message.data);
//   });
//
// For web: use the Pusher Beams JS SDK via dart:js_interop.
// For mobile: use firebase_messaging or the Beams native SDK.
```

---

## File Tree Summary

```
apps/mobile/lib/
├── core/
│   └── config/
│       └── di.dart                          # + _registerChats(), _registerSales()
├── features/
│   ├── auth/
│   │   └── view_models/
│   │       └── auth_view_model.dart         # + _registerPushDevice() after login
│   ├── chats/
│   │   ├── data/
│   │   │   ├── chats_api.dart               # NEW (Phase 6.1)
│   │   │   ├── chats_repository.dart        # NEW (Phase 6.3)
│   │   │   └── realtime_client.dart         # NEW (Phase 7.4)
│   │   ├── models/
│   │   │   └── chat_models.dart             # NEW (Phase 7.1)
│   │   ├── pages/
│   │   │   ├── chat_page.dart               # REWRITTEN (Phase 7.7)
│   │   │   ├── chat_detail_page.dart        # NEW (Phase 7.8)
│   │   │   └── _pages.dart                  # Updated exports
│   │   └── view_models/
│   │       ├── chat_threads_view_model.dart # NEW (Phase 7.5)
│   │       └── chat_view_model.dart         # NEW (Phase 7.6)
│   ├── listings/
│   │   └── pages/
│   │       └── listing_detail_page.dart     # MODIFIED (Phase 6.6–6.8, 6.12)
│   ├── notifications/
│   │   └── data/
│   │       ├── notifications_api.dart       # NEW (Phase 7.9)
│   │       └── notifications_repository.dart # NEW (Phase 7.9)
│   ├── profile/
│   │   └── pages/
│   │       └── profile_page.dart            # MODIFIED (Phase 6.11)
│   └── sales/
│       ├── data/
│       │   ├── sales_api.dart               # NEW (Phase 6.2)
│       │   └── sales_repository.dart        # NEW (Phase 6.4)
│       └── pages/
│           ├── my_purchases_page.dart        # NEW (Phase 6.9)
│           └── my_sales_page.dart            # NEW (Phase 6.10)
├── router/
│   └── us_router.dart                       # MODIFIED (add sales + chat detail routes)
└── pubspec.yaml                             # No new deps needed
```

---

## Acceptance Criteria Checklist

### Phase 6

- [ ] **6.6** ReserveButton calls `POST /listings/{id}/reserve`
- [ ] **6.6** 409 Conflict triggers refresh + toast "no longer available"
- [ ] **6.6** Email not verified → shows verification prompt dialog
- [ ] **6.7** Seller footer shows "Mark as Sold" + "Unreserve" when reserved
- [ ] **6.7** Buyer footer shows "Awaiting meetup" + "Unreserve" when reserved by them
- [ ] **6.8** "Chat with seller" button creates/fetches chat → navigates to chat page
- [ ] **6.9** My Purchases page shows bought items with cursor pagination
- [ ] **6.10** My Sales page shows sold items with cursor pagination
- [ ] **6.11** Profile page has entry points to Purchases and Sales
- [ ] **6.12** Report entry point visible to non-owners

### Phase 7

- [ ] **7.1** ChatThread and ChatMessage freezed models compile and serialize
- [ ] **7.4** RealtimeClient connects to Pusher, subscribes to private-chat-{id}
- [ ] **7.5** ChatThreadsViewModel fetches threads, updates on new messages
- [ ] **7.6** ChatViewModel loads messages, sends via REST, receives via realtime
- [ ] **7.6** Infinite scroll loads older messages
- [ ] **7.7** Chat threads list shows in bottom nav with unread badge
- [ ] **7.8** Chat detail page shows bubbles (sent = right/primary, received = left/muted)
- [ ] **7.8** Read receipts shown (single check / double check)
- [ ] **7.8** Connection indicator shows Pusher status
- [ ] **7.9** Device token registered after login (fire-and-forget)
- [ ] **7.10** Foreground push notification deep-links to chat page
