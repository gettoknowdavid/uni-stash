import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Owns the chat list's scroll behaviour (WhatsApp-style):
///
/// - Tracks whether the user is pinned to the bottom of the list.
/// - Auto-scrolls to the newest message when the chat opens, when the user
///   sends a message, and when a message arrives while already at the
///   bottom.
/// - Shows a "New messages" pill ([newMessagesPill]) when messages arrive
///   while the user is scrolled up; tapping it jumps back to the bottom.
class ChatScrollCoordinator {
  final Signal<bool> _atBottom = signal(true);
  final Signal<int> _unseenCount = signal(0);

  /// Id of the newest message the pill accounting has already seen.
  String? _lastSeenMessageId;

  bool _disposed = false;

  /// Whether the list is scrolled to (or effectively at) the bottom.
  bool get isAtBottom => _atBottom.value;

  /// True when the viewport is within a small tolerance of the bottom.
  static bool _nearBottom(ScrollController controller) {
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.maxScrollExtent - position.pixels < 48;
  }

  /// Called from the page's scroll listener.
  void onScroll(ScrollController controller) {
    if (_disposed) return;
    _atBottom.value = _nearBottom(controller);
  }

  /// Called whenever the messages list changes (from the list's build) so
  /// the pill can account for incoming messages. Idempotent per list
  /// state: it only reacts when the newest message id changes.
  void onMessagesChanged(List<ChatMessage> messages, String currentUserId) {
    if (_disposed || messages.isEmpty) return;
    final newest = messages.last;
    if (newest.id == _lastSeenMessageId) return;

    final incoming = newest.senderId != currentUserId;
    if (_atBottom.value || newest.senderId == currentUserId) {
      // At the bottom (or it's our own send): the message is being read.
      _unseenCount.value = 0;
    } else if (incoming) {
      _unseenCount.value++;
    }
    _lastSeenMessageId = newest.id;
  }

  /// Called when the chat opens / the first page loads — jump immediately.
  void jumpToBottom(ScrollController controller) {
    if (_disposed) return;
    if (!controller.hasClients) {
      // The list may not be laid out yet (initial load); retry next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        jumpToBottom(controller);
      });
      return;
    }
    _doJump(controller);
  }

  void _doJump(ScrollController controller) {
    if (!controller.hasClients) return;
    controller.jumpTo(controller.position.maxScrollExtent);
    _atBottom.value = true;
    _unseenCount.value = 0;
  }

  /// Called after the user sends a message — always scroll to the bottom.
  Future<void> onMessageSent(ScrollController controller) async {
    if (_disposed) return;
    // The optimistic message lands inside a signals `batch`, so the frame
    // with the new item may not exist yet — wait one frame, then animate.
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed) return;
    if (!controller.hasClients) return;
    await controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    if (_disposed) return;
    _atBottom.value = true;
    _unseenCount.value = 0;
  }

  /// Builds the WhatsApp-style "New messages" pill, or nothing when there
  /// are no unseen incoming messages.
  Widget newMessagesPill({required VoidCallback onTap}) {
    return SignalBuilder(
      builder: (context) {
        if (_unseenCount.value == 0) return const SizedBox.shrink();

        final theme = ShadTheme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.foreground.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.arrowDown,
                    size: 14,
                    color: theme.colorScheme.primaryForeground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'New messages',
                    style: theme.textTheme.labelSm.copyWith(
                      color: theme.colorScheme.primaryForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void dispose() {
    _disposed = true;
    _atBottom.dispose();
    _unseenCount.dispose();
  }
}
