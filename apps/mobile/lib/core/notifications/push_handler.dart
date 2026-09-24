import 'dart:async';
import 'dart:convert';

import 'package:uni_stash_mobile/router/_router.dart';

/// A foreground push payload pointing at a chat conversation (guide 7.10).
class ChatPushTarget {
  const ChatPushTarget({
    required this.chatId,
    required this.counterpartName,
    required this.listingTitle,
  });

  final String chatId;
  final String counterpartName;
  final String listingTitle;

  /// The `extra` map the chat detail route expects.
  Map<String, Object> get extra => {
    'chatId': chatId,
    'counterpartName': counterpartName,
    'listingTitle': listingTitle,
  };
}

/// Recursively converts a platform-delivered push `data` map into a
/// string-keyed [Map<String, dynamic>]: platform channels hand back
/// `Map<Object?, Object?>`, and nested payloads (Beams' `info` object) need
/// the same treatment.
Map<String, dynamic> normalizePushData(Map<dynamic, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    result[key.toString()] = value is Map ? normalizePushData(value) : value;
  });
  return result;
}

/// Extracts a chat target from a push `data` payload, or null when the
/// payload doesn't refer to a chat (e.g. a listing-only notification).
///
/// Kept pure and separate from navigation so it is unit-testable.
///
/// Pusher Beams' SDKs conventionally carry custom data nested under an
/// `info` object — iOS `getInitialMessage()` unwraps to it directly and
/// Android's FCM `data` map keeps it as a (possibly JSON-stringified)
/// value — so a payload without a top-level `chat_id` is unwrapped once
/// and retried.
ChatPushTarget? parseChatPush(Map<String, dynamic> data) {
  final chatId = data['chat_id'];
  if (chatId is String && chatId.isNotEmpty) {
    return ChatPushTarget(
      chatId: chatId,
      counterpartName: (data['sender_name'] as String?) ?? 'Unknown',
      listingTitle: (data['listing_title'] as String?) ?? '',
    );
  }

  final info = _asPayload(data['info']);
  if (info != null) return parseChatPush(info);
  return null;
}

/// Installed by the authenticated app shell while it is mounted: turns a
/// foreground-received chat push into an **in-app notification** whose tap
/// opens the conversation (requirement: don't navigate without a tap).
/// Cleared again by `MainShell.dispose`.
///
/// When null (shell not mounted yet), [handleForegroundPush] falls back to
/// navigating directly so the message is never silently dropped.
void Function(ChatPushTarget target)? foregroundChatPushHandler;

/// A chat push arrived while the app was in the foreground (guide 7.10).
///
/// Registered as the Beams foreground handler by `PushNotifications` in
/// `core/notifications/push_notifications.dart`. With the shell mounted the
/// message surfaces as a tappable in-app notification; the fallback keeps
/// the old behaviour when nothing can host one.
void handleForegroundPush(Map<String, dynamic> data) {
  final target = parseChatPush(data);
  if (target == null) return;

  final handler = foregroundChatPushHandler;
  if (handler != null) {
    handler(target);
    return;
  }
  navigateToChat(target);
}

/// The user tapped a notification that launched (or reopened) the app
/// (guide 7.10) — navigate straight into the conversation. Non-chat
/// payloads are ignored.
void handleNotificationTap(Map<String, dynamic> data) {
  final target = parseChatPush(data);
  if (target == null) return;
  navigateToChat(target);
}

/// Opens the chat detail route with the display context from [target].
void navigateToChat(ChatPushTarget target) {
  unawaited(
    routerConfig.push(
      UsRoutes.chatDetailRoute(target.chatId),
      extra: target.extra,
    ),
  );
}

/// Coerces an `info` payload — a map or a JSON-encoded string — into a
/// normalized payload map, or null when it isn't one.
Map<String, dynamic>? _asPayload(Object? value) {
  if (value is Map) return normalizePushData(value);
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return normalizePushData(decoded);
    } on Object catch (_) {
      return null;
    }
  }
  return null;
}
