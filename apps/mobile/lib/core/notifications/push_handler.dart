import 'dart:async';

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

/// Extracts a chat target from a push `data` payload, or null when the
/// payload doesn't refer to a chat (e.g. a listing-only notification).
///
/// Kept pure and separate from navigation so it is unit-testable.
ChatPushTarget? parseChatPush(Map<String, dynamic> data) {
  final chatId = data['chat_id'];
  if (chatId is! String || chatId.isEmpty) return null;

  return ChatPushTarget(
    chatId: chatId,
    counterpartName: (data['sender_name'] as String?) ?? 'Unknown',
    listingTitle: (data['listing_title'] as String?) ?? '',
  );
}

/// Navigates to the chat a foreground push notification refers to
/// (guide 7.10). Non-chat payloads are ignored.
///
/// Wiring — once the native push SDK is configured, register this as the
/// foreground message handler:
///
/// ```dart
/// PushNotifications.onMessageReceived(handleForegroundPush);
/// ```
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
