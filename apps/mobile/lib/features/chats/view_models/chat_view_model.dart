import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

/// View model for a single chat conversation (guide 7.6): message list,
/// sending, cursor pagination, read receipts and realtime updates.
///
/// Realtime payload note: the backend's `message.new` event carries only
/// `chat_id` (see `RealtimeEvent` in apps/api/src/core/realtime), never the
/// message body — so on such an event we refetch the newest page over REST
/// and merge it in, deduplicated by id. The REST row is the source of
/// truth; realtime is only a nudge to refetch.
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

  /// The chat this instance drives.
  final String chatId;

  /// The signed-in user — used to tell "my" messages from the
  /// counterpart's when applying read receipts.
  final String currentUserId;

  /// Chronological message list (oldest at the top for display).
  final Signal<List<ChatMessage>> messages = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isSending = signal(false);
  final Signal<String?> error = signal(null);

  /// Whether the realtime socket is currently up.
  final Signal<bool> isConnected = signal(false);

  String? _nextCursor;
  bool _hasMore = true;
  bool _disposed = false;

  void Function({required bool connected})? _connectionListener;

  late final void Function() loadMessages;
  late final Future<void> Function(String body) sendMessage;

  void _init() {
    loadMessages = action0(() async {
      isLoading.value = true;
      error.value = null;

      final result = await _repository.listMessages(chatId);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          // Backend returns newest-first; reverse for display
          // (oldest at top).
          messages.value = value.messages.reversed.toList();
          _nextCursor = value.nextCursor;
          _hasMore = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;

      // Subscribe to realtime events after the first load.
      _subscribeToRealtime();
    });

    sendMessage = (body) async {
      if (body.trim().isEmpty) return;
      isSending.value = true;

      final result = await _repository.sendMessage(chatId, body.trim());
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          // Optimistically add the sent message. Realtime (or a concurrent
          // refresh) may already have delivered it — dedupe by id.
          final current = messages.value.toList();
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
    _connectionListener = ({required connected}) {
      if (!_disposed) isConnected.value = connected;
    };
    _realtimeClient.onConnectionChanged = _connectionListener;
    isConnected.value = _realtimeClient.isConnected;

    unawaited(
      _realtimeClient.subscribeToChat(
        chatId,
        onNewMessage: (_) => unawaited(_refreshLatest()),
        onReadReceipt: _applyReadReceipt,
      ),
    );
  }

  /// Fetches the newest page and merges it into the loaded history.
  ///
  /// Invoked on `message.new` realtime events, whose payload only carries
  /// `chat_id`. The cursor for older pages is intentionally left alone:
  /// the fresh page only covers the tail, never the already-reached
  /// history boundary.
  Future<void> _refreshLatest() async {
    final result = await _repository.listMessages(chatId);
    if (_disposed) return;

    switch (result) {
      case Success(:final value):
        final page = value.messages.reversed.toList(); // chronological
        final pageIds = page.map((m) => m.id).toSet();
        // Already-loaded messages that aren't in the fresh page are older.
        final older = messages.value.where((m) => !pageIds.contains(m.id));
        messages.value = [...page, ...older];
      case Failure():
        // Transient — the next load/refresh catches up.
        break;
    }
  }

  /// Applies a `message.read` realtime receipt: my messages up to and
  /// including `last_read_message_id` are now read. If the id isn't in the
  /// loaded window, every one of my messages has necessarily been read.
  void _applyReadReceipt(Map<String, dynamic> data) {
    final lastReadId = data['last_read_message_id'];
    final current = messages.value.toList();
    final readIndex = lastReadId is String
        ? current.indexWhere((m) => m.id == lastReadId)
        : -1;

    var changed = false;
    for (var i = 0; i < current.length; i++) {
      if (readIndex >= 0 && i > readIndex) break;
      final message = current[i];
      if (message.senderId == currentUserId && message.readAt == null) {
        current[i] = message.copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) messages.value = current;
  }

  /// Load older messages (scroll to top), deduplicated against what is
  /// already loaded — a realtime refresh may have raced the cursor.
  Future<void> loadMore() async {
    if (!_hasMore || isLoading.value || _disposed) return;

    final result = await _repository.listMessages(
      chatId,
      cursor: _nextCursor,
    );
    if (_disposed) return;

    switch (result) {
      case Success(:final value):
        final existing = messages.value.map((m) => m.id).toSet();
        // Page window is newest-first; reverse to chronological and drop
        // anything already present.
        final older = value.messages.reversed
            .where((m) => !existing.contains(m.id))
            .toList();
        if (older.isNotEmpty) {
          messages.value = [...older, ...messages.value];
        }
        _nextCursor = value.nextCursor;
        _hasMore = value.nextCursor != null;
      case Failure():
        break;
    }
  }

  /// Mark the counterpart's messages as read (when the user opens the
  /// chat / scrolls to the bottom).
  Future<void> markRead() => _repository.markRead(chatId);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _realtimeClient.unsubscribeFromChat(chatId);
    if (identical(_realtimeClient.onConnectionChanged, _connectionListener)) {
      _realtimeClient.onConnectionChanged = null;
    }
    messages.dispose();
    isLoading.dispose();
    isSending.dispose();
    error.dispose();
    isConnected.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
