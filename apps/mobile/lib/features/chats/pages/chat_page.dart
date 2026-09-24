import 'dart:async';

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';
import 'package:uni_stash_mobile/features/chats/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Chat threads list (guide 7.7) — the CHAT tab of the bottom nav.
///
/// The [ChatThreadsViewModel] is an authenticated-scope singleton shared
/// with `MainShell`, so the nav bar's unread badge and this list always
/// read the same source of truth.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      header: UsPageHeader(title: Text('CHATS')),
      gutters: .zero,
      body: _ChatThreadsList(),
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
          return const Center(child: Spinner());
        }

        if (error != null && threads.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(error, textAlign: .center, style: theme.textTheme.muted),
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

        return CustomMaterialIndicator(
          onRefresh: () async => model.fetch(),
          indicatorBuilder: (context, refreshing) => const Spinner(),
          child: ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, _) => ShadSeparator.horizontal(
              margin: const .symmetric(horizontal: 16),
              color: theme.colorScheme.border,
            ),
            itemBuilder: (context, index) {
              return _ChatThreadTile(thread: threads[index]);
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

    // Deliberately not a Material ListTile — the app is moving off
    // Material widgets, so the tile is a plain shadcn-style layout like
    // listing_card (ShadGestureDetector keeps hover/tooltip behaviour).
    return ShadGestureDetector(
      behavior: .opaque,
      onTap: () {
        // Clear the local badge, then open the conversation — ChatViewModel
        // marks it read server-side on load, so the badge stays cleared
        // after the next thread fetch.
        di<ChatThreadsViewModel>().markThreadRead(thread.id);
        unawaited(
          context.push(
            UsRoutes.chatDetailRoute(thread.id),
            extra: {
              'chatId': thread.id,
              'counterpartName': thread.counterpartName,
              'listingTitle': thread.listingTitle,
            },
          ),
        );
      },
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            UsAvatar(
              name: thread.counterpartName,
              photoUrl: thread.counterpartPhotoUrl,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: .stretch,
                mainAxisSize: .min,
                children: [
                  Text(
                    thread.listingTitle,
                    style: theme.textTheme.p.copyWith(
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                  Text(
                    thread.lastMessagePreview ?? 'No messages yet',
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: .center,
              mainAxisSize: .min,
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
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}
