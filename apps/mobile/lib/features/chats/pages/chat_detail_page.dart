import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/chats/data/_data.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/view_models/_view_models.dart';
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
    super.key,
  });

  final String chatId;
  final String counterpartName;
  final String listingTitle;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
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
            currentUserId: di<UserViewModel>().currentUser.value?.id ?? '',
          ),
          onCreated: (model) async => model.loadMessages(),
          dispose: (vm) => vm.dispose(),
        );
      },
    );

    // Reaching the top of the list loads older messages (infinite scroll).
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 0) {
      unawaited(di<ChatViewModel>().loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    // popScope() is async but dispose() is sync, so the pop is fired,
    // not awaited — see [popPageScope].
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
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
              Expanded(
                child: _ChatBody(
                  currentUserId: currentUserId,
                  scrollController: _scrollController,
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
          unawaited(di<ChatViewModel>().sendMessage(text));
          _inputController.clear();
        },
      ),
    );
  }
}

/// Slim status strip under the header surfacing the Pusher socket state
/// (guide 7.8 acceptance: connection indicator). Hidden while connected.
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
  });

  final String currentUserId;
  final ScrollController scrollController;

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

        return ListView.builder(
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

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

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
            children: [
              Expanded(
                child: ShadInputFormField(
                  id: 'chat-message',
                  controller: controller,
                  autocorrect: false,
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
