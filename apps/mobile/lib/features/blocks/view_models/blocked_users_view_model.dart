import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/blocks/data/blocks_repository.dart';
import 'package:uni_stash_mobile/features/blocks/models/models.dart';

/// Page-scoped ViewModel for the blocked-users page (settings).
class BlockedUsersViewModel implements Disposable {
  BlockedUsersViewModel(this._repository);

  final BlocksRepository _repository;

  final Signal<List<BlockedUser>> blockedUsers = signal(const []);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<String?> busyUserId = signal(null);
  bool _disposed = false;

  Future<void> fetch() async {
    isLoading.value = true;
    error.value = null;
    final result = await _repository.listBlocked();
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        blockedUsers.value = value;
      case Failure(:final message):
        error.value = message;
    }
    isLoading.value = false;
  }

  Future<bool> unblock(BlockedUser user) async {
    busyUserId.value = user.blockedId;
    final result = await _repository.unblock(user.blockedId);
    if (_disposed) return false;
    switch (result) {
      case Success():
        blockedUsers.value = [
          for (final entry in blockedUsers.value)
            if (entry.blockedId != user.blockedId) entry,
        ];
      case Failure(:final message):
        error.value = message;
    }
    busyUserId.value = null;
    return result is Success;
  }

  void dispose() {
    _disposed = true;
    blockedUsers.dispose();
    isLoading.dispose();
    error.dispose();
    busyUserId.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}

/// One-shot helper used by dialogs (seller card / chat) that block a user
/// without needing a full page-scoped ViewModel.
Future<bool> blockUser(GetIt locator, String userId) async {
  final result = await locator<BlocksRepository>().block(userId);
  return result is Success;
}
