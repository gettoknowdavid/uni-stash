import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/features/notifications/data/_data.dart';
import 'package:uni_stash_mobile/features/notifications/models/notifications_dto.dart';
import 'package:uni_stash_mobile/features/notifications/view_models/notifications_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// NOTIFICATIONS inbox (guide 7.x): in-app notification history with
/// per-item read/delete and a mark-all action. Tapping a chat notification
/// deep-links into the conversation.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'notificationsPage',
      init: (getIt) {
        getIt.registerLazySingleton<NotificationsViewModel>(
          () => NotificationsViewModel(di<NotificationsRepository>()),
          dispose: (model) => model.dispose(),
        );
      },
    );
    unawaited(di<NotificationsViewModel>().fetch());
  }

  @override
  void dispose() {
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      gutters: .all(16),
      header: UsPageHeader(
        title: Text('NOTIFICATIONS'),
        actions: [
          _MarkAllButton(),
        ],
      ),
      body: _InboxBody(),
    );
  }
}

class _MarkAllButton extends SignalWidget {
  const _MarkAllButton();

  @override
  Widget build(BuildContext context) {
    final model = di<NotificationsViewModel>();
    final unread = model.unreadCount.value;
    if (unread == 0) return const SizedBox.shrink();
    return ShadButton.ghost(
      height: 30,
      padding: const .symmetric(horizontal: 12),
      onPressed: model.markAllRead,
      child: Text(
        'MARK ALL READ',
        style: ShadTheme.of(context).textTheme.labelSm,
      ),
    );
  }
}

class _InboxBody extends SignalWidget {
  const _InboxBody();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<NotificationsViewModel>();
    final items = model.items.value;
    final isLoading = model.isLoading.value;
    final isLoadingMore = model.isLoadingMore.value;
    final error = model.error.value;

    if (isLoading && items.isEmpty) {
      return const Center(child: Spinner());
    }

    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(error, style: theme.textTheme.muted, textAlign: .center),
            const SizedBox(height: 16),
            ShadButton.outline(
              onPressed: model.fetch,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              LucideIcons.bellOff,
              size: 40,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text("You're all caught up", style: theme.textTheme.muted),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) {
          unawaited(model.loadMore());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: model.refresh,
        child: ListView.separated(
          itemCount: items.length + (isLoadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return const Padding(
                padding: .symmetric(vertical: 16),
                child: Center(child: Spinner()),
              );
            }
            final item = items[index];
            return Dismissible(
              key: ValueKey(item.id),
              direction: .endToStart,
              background: Container(
                alignment: .centerRight,
                padding: const .only(right: 24),
                color: theme.colorScheme.destructive,
                child: const Icon(LucideIcons.trash2, color: Colors.white),
              ),
              onDismissed: (_) => model.delete(item.id),
              child: _NotificationTile(notification: item),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  IconData get _icon => switch (notification.type) {
        'chat.message' => LucideIcons.messageCircle,
        'sale.completed' => LucideIcons.shoppingBag,
        'review.received' => LucideIcons.star,
        _ => LucideIcons.bell,
      };

  /// Deep-link target for tappable notifications. Chat messages open the
  /// conversation; other types are inert for now.
  String? get _route {
    final data = notification.data;
    if (data == null) return null;
    final chatId = data['chat_id'];
    if (notification.type == 'chat.message' && chatId is String) {
      return UsRoutes.chatDetailRoute(chatId);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUnread = notification.readAt == null;
    final route = _route;

    return GestureDetector(
      behavior: .opaque,
      onTap: () async {
        await di<NotificationsViewModel>().markRead(notification.id);
        if (!context.mounted) return;
        if (route != null) await context.push(route);
      },
      onLongPress: () => di<NotificationsViewModel>().delete(notification.id),
      child: ShadCard(
        padding: const .symmetric(horizontal: 16, vertical: 14),
        backgroundColor: isUnread ? theme.colorScheme.muted : null,
        leading: Icon(
          _icon,
          size: 24,
          color: isUnread
              ? theme.colorScheme.primary
              : theme.colorScheme.mutedForeground,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: theme.textTheme.p.copyWith(
                  fontWeight: isUnread ? .w700 : .w500,
                ),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
            if (isUnread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: .circle,
                ),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              notification.body,
              style: theme.textTheme.small,
              maxLines: 2,
              overflow: .ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              timeago.format(notification.createdAt),
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
