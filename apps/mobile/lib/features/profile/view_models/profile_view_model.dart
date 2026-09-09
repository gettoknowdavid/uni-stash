import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';

/// Page-scoped ViewModel that drives the profile screen.
///
/// Holds a DB-fresh copy of the signed-in user's profile, fetched via
/// [ProfileRepository.getProfile] (GET /auth/me) — separate from the cached
/// session user in AuthViewModel, so the screen can show a refresh affordance
/// and pick up server-side changes (display name, verification) without
/// touching session state.
class ProfileViewModel implements Disposable {
  ProfileViewModel(this._repository) {
    _init();
  }

  final ProfileRepository _repository;

  final Signal<User?> profile = signal(null);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  late final void Function() fetch;

  Future<void> _fetch() async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.getProfile();
    switch (result) {
      case Success(:final value):
        profile.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isLoading.value = false;
  }

  void _init() {
    fetch = action0(() async {
      await _fetch();
    });
  }

  void reset() {
    profile.value = null;
    isLoading.value = false;
    error.value = null;
  }

  void dispose() {
    profile.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
