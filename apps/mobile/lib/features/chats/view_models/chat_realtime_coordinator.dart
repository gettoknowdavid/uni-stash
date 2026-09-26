import 'dart:async';

import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/notifications/in_app_chat_notifier.dart';
import 'package:uni_stash_mobile/core/notifications/push_handler.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/open_chat.dart';
import 'package:uni_stash_mobile/features/chats/view_models/chat_threads_view_model.dart';
import 'package:uni_stash_mobile/router/_router.dart';

/// Session-lived bridge between the realtime transport and the UI
/// (authenticated shell scope; started/stopped by `MainShell`).
///
/// Owns the `private-user-{me}` subscription — the channel the backend
/// publishes `message.new` to for messages *addressed to this user*, in any
/// chat (see `apps/api/src/features/chats/handlers.rs`). That is what makes
/// requirements 1 and 4 work for chats the user is **not** viewing:
///
/// * the thread list (previews, order, unread badge) refreshes live;
/// * an in-app notification pops for messages in other chats — tapping it
///   opens the conversation;
/// * when the chat *is* open, no notification is shown: the open
///   `ChatViewModel`'s own subscription updates the list in place.
///
/// Foreground push notifications (Beams, delivered while the app is open)
/// funnel through the same notifier via [foregroundChatPushHandler], so the
/// realtime event and the FCM foreground delivery of the same message are
/// deduplicated to a single notification.
class ChatRealtimeCoordinator {
  ChatRealtimeCoordinator({
    required RealtimeClient realtimeClient,
    required ChatThreadsViewModel threads,
    required InAppChatNotifier notifier,
    required String currentUserId,
    required Logger logger,
  }) : _realtime = realtimeClient,
       _threads = threads,
       _notifier = notifier,
       _currentUserId = currentUserId,
       _logger = logger;

  final RealtimeClient _realtime;
  final ChatThreadsViewModel _threads;
  final InAppChatNotifier _notifier;
  final String _currentUserId;
  final Logger _logger;

  RealtimeSubscription? _subscription;
  void Function(ChatPushTarget target)? _pushHook;
  bool _started = false;

  /// Whether the coordinator is running.
  bool get isStarted => _started;

  /// Subscribes to the user's notification channel and installs the
  /// foreground-push hook. Idempotent. The shell attaches the host context
  /// to the notifier separately (it owns the widget tree).
  void start() {
    if (_started) return;
    if (_currentUserId.isEmpty) {
      _logger.w('Chat realtime: no current user — not starting');
      return;
    }
    _started = true;
    _pushHook = _onForegroundPush;
    foregroundChatPushHandler = _pushHook;
    unawaited(_subscribeUserChannel());
  }

  Future<void> _subscribeUserChannel() async {
    final subscription = await _realtime.subscribeToUserChannel(
      _currentUserId,
      onNewMessage: _onUserMessageNew,
    );
    if (!_started) {
      subscription.cancel();
      return;
    }
    _subscription = subscription;
  }

  void stop() {
    if (!_started) return;
    _started = false;
    if (identical(foregroundChatPushHandler, _pushHook)) {
      foregroundChatPushHandler = null;
    }
    _subscription?.cancel();
    _subscription = null;
  }

  /// App returned to the foreground — make sure the socket and its
  /// subscriptions are still alive (the OS may have killed the socket
  /// while dozed without a state callback reaching us in time).
  void onAppResumed() => _realtime.ensureLive();

  // -------------------------------------------------------------------------
  // Realtime: `message.new` on private-user-{me}
  // -------------------------------------------------------------------------

  void _onUserMessageNew(Map<String, dynamic> data) {
    final chatId = data['chat_id'];
    if (chatId is! String || chatId.isEmpty) return;

    if (OpenChat.isOpen(chatId)) {
      // The open ChatViewModel refetches messages and marks them read;
      // keep the badge and preview in sync with it.
      unawaited(
        _threads.fetch().whenComplete(() => _threads.markThreadRead(chatId)),
      );
      return;
    }
    unawaited(_refreshAndNotify(chatId));
  }

  Future<void> _refreshAndNotify(String chatId) async {
    await _threads.fetch();
    if (!_started) return;
    _notify(chatId, fallbackName: null);
  }

  // -------------------------------------------------------------------------
  // Foreground push (Beams) — same notification path as realtime
  // -------------------------------------------------------------------------

  void _onForegroundPush(ChatPushTarget target) {
    if (!_started) return;
    // Already looking at this conversation — the realtime subscription on
    // the chat channel updated the list in place; a notification would
    // only duplicate what the user just saw.
    if (OpenChat.isOpen(target.chatId)) return;
    _notify(target.chatId, fallbackName: target.counterpartName);
    // The push payload carries no thread context — refresh so the badge,
    // preview and the notification body catch up.
    unawaited(_threads.fetch());
  }

  // -------------------------------------------------------------------------
  // Notification + navigation
  // -------------------------------------------------------------------------

  void _notify(String chatId, {required String? fallbackName}) {
    final thread = _threadFor(chatId);
    final String title;
    if (thread != null) {
      title = 'New message from ${thread.counterpartName}';
    } else if (fallbackName != null && fallbackName != 'Unknown') {
      title = 'New message from $fallbackName';
    } else {
      title = 'New message';
    }
    _notifier.show(
      chatId: chatId,
      title: title,
      body: thread?.lastMessagePreview,
      onOpen: () => _openChat(chatId, thread),
    );
  }

  /// Mirrors the thread-tile tap: clear the local badge, then push the
  /// conversation with the display context the header needs.
  void _openChat(String chatId, ChatThread? thread) {
    _threads.markThreadRead(chatId);
    unawaited(
      routerConfig.push(
        UsRoutes.chatDetailRoute(chatId),
        extra: <String, Object>{
          'chatId': chatId,
          'counterpartId': thread?.counterpartId ?? '',
          'counterpartName': thread?.counterpartName ?? 'Chat',
          'listingTitle': thread?.listingTitle ?? '',
        },
      ),
    );
  }

  ChatThread? _threadFor(String chatId) {
    for (final thread in _threads.threads.value) {
      if (thread.id == chatId) return thread;
    }
    return null;
  }
}
