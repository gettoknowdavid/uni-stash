import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shows tappable in-app "new message" notifications while the app is open
/// (guide 7.8/7.10, requirement: receiver not on the chat detail screen
/// sees an in-app notification, tapping it opens the chat).
///
/// A single instance is shared by the realtime coordinator (Pusher
/// `message.new` on the user's channel) and the Beams foreground push
/// handler, and doubles as the **dedup** point between them: the same
/// chat can produce both signals within a second (socket event + FCM
/// foreground delivery), but the user must only see one notification.
class InAppChatNotifier {
  InAppChatNotifier({Logger? logger}) : _logger = logger;

  final Logger? _logger;

  /// Same-chat re-notify window — covers the realtime↔push double fire.
  static const Duration dedupWindow = Duration(seconds: 6);

  BuildContext? _context;
  final Map<String, DateTime> _lastShownAt = <String, DateTime>{};

  /// Whether a notification can currently be shown (shell mounted).
  bool get isAttached => _context != null && _context!.mounted;

  /// Host context — must sit below `ShadToaster` (installed in the app
  /// builder) so `ShadToaster.of` resolves. Called by the authenticated
  /// shell on mount and cleared on unmount.
  void attach(BuildContext context) => _context = context;

  void detach() => _context = null;

  /// Pure decision (unit-testable): show at most one notification per chat
  /// within [dedupWindow].
  bool shouldShow(String chatId, DateTime now) {
    final last = _lastShownAt[chatId];
    return last == null || now.difference(last) >= dedupWindow;
  }

  /// Records [chatId] as notified (used by [shouldShow] callers that make
  /// the decision before a context exists, e.g. tests and push fallbacks).
  void markShown(String chatId, DateTime now) {
    _lastShownAt[chatId] = now;
    _lastShownAt.removeWhere(
      (_, at) => now.difference(at) > const Duration(minutes: 5),
    );
  }

  /// Shows the notification; returns false when nothing was shown (no
  /// context, or deduped against a moment-ago notification for this chat).
  bool show({
    required String chatId,
    required String title,
    required VoidCallback onOpen,
    String? body,
  }) {
    final context = _context;
    if (context == null || !context.mounted) {
      _logger?.d('In-app notification skipped (no host): $title');
      return false;
    }

    final now = DateTime.now();
    if (!shouldShow(chatId, now)) {
      _logger?.d('In-app notification deduped for $chatId');
      return false;
    }
    markShown(chatId, now);

    final toaster = ShadToaster.maybeOf(context);
    if (toaster == null) return false;
    toaster.show(
      ShadToast(
        title: Text(title),
        description: body == null || body.isEmpty ? null : Text(body),
        duration: const Duration(seconds: 6),
        action: ShadButton.outline(
          onPressed: onOpen,
          child: const Text('View'),
        ),
      ),
    );
    return true;
  }
}
