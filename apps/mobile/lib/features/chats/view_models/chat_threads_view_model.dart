import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/models/models.dart';

/// View model for the chat threads list (bottom nav "Chat" tab) — guide 7.5.
///
/// Manages the list of threads and the aggregate unread count for the
/// badge. The page only reads signals and calls [fetch]/[markThreadRead];
/// all repository access stays here.
class ChatThreadsViewModel implements Disposable {
  ChatThreadsViewModel(this._repository) {
    _init();
  }

  final ChatsRepository _repository;

  final Signal<List<ChatThread>> threads = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  /// Total unread count across all threads (for the badge dot).
  late final ReadonlySignal<int> unreadCount = computed(
    () => threads.value.fold(0, (sum, t) => sum + t.unreadCount),
  );

  late final void Function() fetch;

  bool _disposed = false;

  void _init() {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;

      final result = await _repository.listThreads();
      if (_disposed) return;

      // One notification for the whole outcome (threads/error + isLoading).
      batch(() {
        switch (result) {
          case Success(:final value):
            threads.value = value;
          case Failure(:final message):
            error.value = message;
        }

        isLoading.value = false;
      });
    });
  }

  /// Called when a new message arrives via realtime.
  /// Moves the thread to the top with the new preview and bumps its
  /// unread count.
  void onNewMessage(String chatId, String preview) {
    final current = threads.value.toList();
    final index = current.indexWhere((t) => t.id == chatId);
    if (index == -1) return;

    final thread = current[index];
    current.removeAt(index);
    current.insert(
      0,
      thread.copyWith(
        lastMessagePreview: preview,
        lastMessageAt: DateTime.now(),
        unreadCount: thread.unreadCount + 1,
      ),
    );
    threads.value = current;
  }

  /// Reset unread count for a thread (when the user opens it).
  void markThreadRead(String chatId) {
    final current = threads.value.toList();
    final index = current.indexWhere((t) => t.id == chatId);
    if (index == -1) return;

    current[index] = current[index].copyWith(unreadCount: 0);
    threads.value = current;
  }

  void dispose() {
    _disposed = true;
    threads.dispose();
    isLoading.dispose();
    error.dispose();
    unreadCount.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
