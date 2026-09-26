import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/blocks/pages/block_user_dialog.dart';
import 'package:uni_stash_mobile/features/chats/data/_data.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/open_chat.dart';
import 'package:uni_stash_mobile/features/chats/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/chats/widgets/chat_scroll_coordinator.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Real chat conversation page (guide 7.8): message bubbles with read
/// receipts, a Pusher connection indicator, infinite scroll back through
/// history and an input bar.
///
/// One [ChatViewModel] per visit, owned by a per-chat GetIt scope that is
/// popped on dispose (same pattern as the listing detail page).
class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({
    required this.chatId,
    required this.counterpartName,
    required this.listingTitle,
    this.counterpartId,
    super.key,
  });

  final String chatId;
  final String counterpartName;
  final String listingTitle;

  /// The other participant's user id. Provided by thread-list navigations;
  /// deep links (notifications) may omit it, in which case the page
  /// fetches it via GET /chats/{id} before showing the profile/block menu
  /// actions.
  final String? counterpartId;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _scrollCoordinator = ChatScrollCoordinator();

  /// Resolved lazily: from the constructor extra, or fetched via
  /// GET /chats/{id} on first menu open (deep links may omit it).
  String? _counterpartId;

  @override
  void initState() {
    super.initState();
    // Messages for THIS chat update the list in place; every other chat
    // raises an in-app notification instead (see OpenChat).
    OpenChat.open(widget.chatId);
    _scopeName = pushPageScope(
      baseName: 'chat-${widget.chatId}',
      init: (getIt) {
        getIt.registerLazySingletonAsync<ChatViewModel>(
          () async => ChatViewModel(
            di<ChatsRepository>(),
            di<RealtimeClient>(),
            chatId: widget.chatId,
            currentUserId: di<UserViewModel>().currentUser.value?.id ?? '',
            // Sender-side: refresh the thread list immediately so the
            // preview/order update without waiting for a push round-trip.
            onMessageSent: () => unawaited(di<ChatThreadsViewModel>().fetch()),
          ),
          onCreated: (model) async => model.loadMessages(),
          dispose: (vm) => vm.dispose(),
        );
      },
    );

    _counterpartId = widget.counterpartId;

    // Reaching the top of the list loads older messages (infinite scroll);
    // the coordinator also tracks "at bottom" for the new-messages pill.
    _scrollController.addListener(_onScroll);
    // Jump to the newest message as soon as the view model is ready.
    unawaited(
      di.isReady<ChatViewModel>().then(
        (_) => _scrollCoordinator.jumpToBottom(_scrollController),
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 0) {
      unawaited(di<ChatViewModel>().loadMore());
    }
    _scrollCoordinator.onScroll(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollCoordinator.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    OpenChat.close(widget.chatId);
    // popScope() is async but dispose() is sync, so the pop is fired,
    // not awaited — see [popPageScope].
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  /// Resolves the counterpart id if not already known (deep-link case):
  /// fetches the thread metadata once, caches the result.
  Future<String?> _resolveCounterpartId() async {
    if (_counterpartId != null) return _counterpartId;
    final result = await di<ChatsRepository>().getChat(widget.chatId);
    switch (result) {
      case Success(:final value):
        _counterpartId = value.counterpartId;
        return _counterpartId;
      case Failure():
        return null;
    }
  }

  /// Chat app-bar menu: view the counterpart's profile, block them.
  Future<void> _openMenu(BuildContext context) async {
    final counterpartId = await _resolveCounterpartId();
    if (!context.mounted) return;

    await showShadSheet<void>(
      context: context,
      side: .bottom,
      builder: (sheetContext) => ShadSheet(
        title: Text(widget.counterpartName),
        description: Text(widget.listingTitle),
        actions: [
          ShadButton.outline(
            onPressed: () => sheetContext.pop(),
            child: const Text('CLOSE'),
          ),
        ],
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            _MenuAction(
              icon: LucideIcons.user,
              label: 'View profile',
              onTap: () {
                sheetContext.pop();
                if (counterpartId != null) {
                  unawaited(
                    context.push(UsRoutes.userProfileRoute(counterpartId)),
                  );
                }
              },
            ),
            _MenuAction(
              icon: LucideIcons.userX,
              label: 'Block this user',
              destructive: true,
              onTap: () {
                sheetContext.pop();
                if (counterpartId != null) {
                  unawaited(
                    showBlockUserDialog(
                      context,
                      userId: counterpartId,
                      userName: widget.counterpartName,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final currentUserId = di<UserViewModel>().currentUser.value?.id ?? '';

    return UsPage(
      header: UsPageHeader(
        title: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          mainAxisAlignment: .center,
          children: [
            Text(
              widget.counterpartName,
              style: theme.textTheme.h4,
              maxLines: 1,
              overflow: .ellipsis,
            ),
            Text(
              widget.listingTitle,
              style: theme.textTheme.labelSm.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ],
        ),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onPressed: () => unawaited(_openMenu(context)),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: di.isReady<ChatViewModel>(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != .done) {
            return const Center(child: Spinner());
          }
          return Column(
            children: [
              const _ConnectionBanner(),
              const _SendErrorBanner(),
              Expanded(
                child: _ChatBody(
                  currentUserId: currentUserId,
                  scrollController: _scrollController,
                  coordinator: _scrollCoordinator,
                ),
              ),
            ],
          );
        },
      ),
      footer: _ChatInputBar(
        controller: _inputController,
        onSend: () {
          final text = _inputController.text.trim();
          if (text.isEmpty) return;
          unawaited(
            di<ChatViewModel>().sendMessage(text).then(
              (_) => _scrollCoordinator.onMessageSent(_scrollController),
            ),
          );
          _inputController.clear();
        },
      ),
    );
  }
}

/// Surfaces send failures. A 403 between a blocked pair shows the clear
/// "can no longer message" copy instead of a generic error.
class _SendErrorBanner extends SignalWidget {
  const _SendErrorBanner();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final error = di<ChatViewModel>().error.value;
    if (error == null) return const SizedBox.shrink();

    // The blocked-pair 403 surfaces as a permission failure; show the
    // actionable copy rather than the generic permission text.
    final isBlockedPair =
        error == "You don't have permission to do that.";
    final message =
        isBlockedPair ? 'You can no longer message this user.' : error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.destructive.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.destructive),
        ),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 16,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.labelSm.copyWith(
                  color: theme.colorScheme.destructive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalBuilder(
      builder: (context) {
        final isConnected = di<ChatViewModel>().isConnected.value;
        if (isConnected) return const SizedBox.shrink();

        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.muted,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.border),
            ),
          ),
          child: Padding(
            padding: const .symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Spinner(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reconnecting for live updates — messages still send',
                    style: theme.textTheme.labelSm.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({
    required this.currentUserId,
    required this.scrollController,
    required this.coordinator,
  });

  final String currentUserId;
  final ScrollController scrollController;
  final ChatScrollCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalBuilder(
      builder: (context) {
        final model = di<ChatViewModel>();
        final messages = model.messages.value;
        final isLoading = model.isLoading.value;

        if (isLoading && messages.isEmpty) {
          return const Center(child: Spinner());
        }

        if (messages.isEmpty) {
          return Center(
            child: Text(
              'Send a message to start chatting',
              style: theme.textTheme.muted,
            ),
          );
        }

        coordinator.onMessagesChanged(messages, currentUserId);

        return Stack(
          alignment: .bottomCenter,
          children: [
            ListView.builder(
              controller: scrollController,
              padding: const .symmetric(vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return _MessageBubble(
                  message: message,
                  isMe: message.senderId == currentUserId,
                );
              },
            ),
            coordinator.newMessagesPill(
              onTap: () => coordinator.jumpToBottom(scrollController),
            ),
          ],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = isMe
        ? theme.colorScheme.primaryForeground
        : theme.colorScheme.foreground;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const .only(bottom: 8),
        padding: const .symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? theme.colorScheme.primary : theme.colorScheme.muted,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .end,
          children: [
            Text(
              message.body,
              style: theme.textTheme.p.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: .min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: theme.textTheme.labelSm.copyWith(
                    color: isMe
                        ? foreground.withValues(alpha: 0.6)
                        : theme.colorScheme.mutedForeground,
                    fontSize: 10,
                  ),
                ),
                // Read receipts: single check while unread, double check
                // once the counterpart has read it (guide 7.8).
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt != null
                        ? LucideIcons.checkCheck
                        : LucideIcons.check,
                    size: 12,
                    color: message.readAt != null
                        ? foreground
                        : foreground.withValues(alpha: 0.6),
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

/// One row in the chat app-bar menu (no Material — plain shadcn-style
/// layout, matching the rest of the chat UI).
class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = destructive ? theme.colorScheme.destructive : null;
    return GestureDetector(
      behavior: .opaque,
      onTap: onTap,
      child: Padding(
        padding: const .symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: theme.textTheme.p.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({required this.controller, required this.onSend});

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
            // Keep the send button pinned to the last line as the field
            // grows to multiple lines.
            crossAxisAlignment: .end,
            children: [
              Expanded(
                child: ShadInputFormField(
                  id: 'chat-message',
                  controller: controller,
                  autocorrect: false,
                  // Grows like a normal chat bar: one line while short,
                  // up to five lines for longer drafts; past that the
                  // field scrolls *vertically* (a single-line input
                  // scrolls horizontally instead, which feels wrong).
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: .multiline,
                  // Keeps the IME's Send key wired to onSubmitted even
                  // though the field is multiline.
                  textInputAction: .send,
                  onSubmitted: (_) => onSend(),
                  placeholder: const Text('Type a message...'),
                ),
              ),
              const SizedBox(width: 8),
              // Deliberately not Material's IconButton — shadcn gesture
              // wrapper keeps hover/tooltip behaviour.
              ShadGestureDetector(
                behavior: .opaque,
                onTap: onSend,
                child: Padding(
                  padding: const .all(8),
                  child: Icon(
                    LucideIcons.send,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
