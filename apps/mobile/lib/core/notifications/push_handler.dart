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

/// Navigates to the chat a push notification refers to (guide 7.10).
/// Non-chat payloads are ignored.
///
/// Registered as the Beams foreground handler (and cold-start tap handler)
/// by `PushNotifications` in `core/notifications/push_notifications.dart`.
void handleForegroundPush(Map<String, dynamic> data) {
  final target = parseChatPush(data);
  if (target == null) return;

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
