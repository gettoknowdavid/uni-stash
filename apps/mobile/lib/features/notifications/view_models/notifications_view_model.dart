import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/notifications/data/notifications_repository.dart';
import 'package:uni_stash_mobile/features/notifications/models/notifications_dto.dart';

/// Page-scoped view model for the notifications inbox: cursor-paginated
/// fetch + optimistic read / delete with server reconciliation.
class NotificationsViewModel implements Disposable {
  NotificationsViewModel(this._repository);

  final INotificationsRepository _repository;

  final FlutterSignal<List<AppNotification>> items =
      signal<List<AppNotification>>([]);
  final FlutterSignal<bool> isLoading = signal(false);
  final FlutterSignal<bool> isLoadingMore = signal(false);
  final FlutterSignal<String?> error = signal<String?>(null);
  final FlutterSignal<int> unreadCount = signal(0);
  final FlutterSignal<bool> hasMore = signal(true);

  bool _disposed = false;
  String? _cursor;

  Future<void> fetch() async {
    isLoading.value = true;
    error.value = null;
    _cursor = null;
    hasMore.value = true;

    final result = await _repository.listInbox();
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        items.value = value.notifications;
        unreadCount.value = value.unreadCount;
        _cursor = value.nextCursor;
        hasMore.value = value.nextCursor != null;
      case Failure(:final message):
        error.value = message;
    }
    isLoading.value = false;
  }

  /// Pull-to-refresh: re-fetches the first page.
  Future<void> refresh() => fetch();

  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;

    isLoadingMore.value = true;
    final result = await _repository.listInbox(cursor: _cursor);
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        items.value = [...items.value, ...value.notifications];
        unreadCount.value = value.unreadCount;
        _cursor = value.nextCursor;
        hasMore.value = value.nextCursor != null;
      case Failure():
        break; // stop paginating silently on failure
    }
    isLoadingMore.value = false;
  }

  /// Optimistically marks [id] read; reconciles with a refresh on failure.
  Future<void> markRead(String id) async {
    final index = items.value.indexWhere((n) => n.id == id);
    if (index == -1) return;
    final target = items.value[index];
    if (target.readAt != null) return;

    final updated = [...items.value];
    updated[index] = target.copyWith(readAt: DateTime.now());
    items.value = updated;
    if (unreadCount.value > 0) unreadCount.value--;

    final result = await _repository.markRead(id);
    if (result is Failure && !_disposed) await refresh();
  }

  /// Marks everything read (optimistic, count zeroed).
  Future<void> markAllRead() async {
    final now = DateTime.now();
    items.value = [
      for (final n in items.value)
        if (n.readAt != null) n else n.copyWith(readAt: now),
    ];
    unreadCount.value = 0;

    final result = await _repository.markAllRead();
    if (result is Failure && !_disposed) await refresh();
  }

  /// Optimistically removes [id]; rolls back via refresh on failure.
  Future<void> delete(String id) async {
    final snapshot = items.value;
    final previousUnread = unreadCount.value;
    final removed = snapshot.where((n) => n.id == id).firstOrNull;
    if (removed == null) return;

    items.value = snapshot.where((n) => n.id != id).toList();
    if (removed.readAt == null && unreadCount.value > 0) unreadCount.value--;

    final result = await _repository.delete(id);
    if (result is Failure && !_disposed) {
      items.value = snapshot;
      unreadCount.value = previousUnread;
    }
  }

  void dispose() {
    _disposed = true;
    items.dispose();
    isLoading.dispose();
    isLoadingMore.dispose();
    error.dispose();
    unreadCount.dispose();
    hasMore.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
