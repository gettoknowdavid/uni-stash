import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
export 'package:uni_stash_mobile/features/profile/data/profile_repository.dart'
    show ProfileStats;

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
  final Signal<bool> isUpdating = signal(false);
  final Signal<String?> updateError = signal(null);
  final Signal<bool> updateSuccess = signal(false);

  /// Real counts fetched from the listings API.
  final Signal<ProfileStats> stats = signal(
    const ProfileStats(activeListings: 0, itemsSold: 0),
  );

  late final void Function() fetch;

  Future<void> _fetch() async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.getProfile();
    switch (result) {
      case Success(:final value):
        profile.value = value;
        // Fetch stats in parallel after profile loads.
        unawaited(_fetchStats(value.id));
      case Failure(:final message):
        error.value = message;
    }

    isLoading.value = false;
  }

  Future<void> _fetchStats(String userId) async {
    final result = await _repository.getStats(userId);
    switch (result) {
      case Success(:final value):
        stats.value = value;
      case Failure(message: final _):
        // Stats failure is non-fatal — show zeros.
        stats.value = const ProfileStats(activeListings: 0, itemsSold: 0);
    }
  }

  Future<void> updateProfile({
    String? displayName,
    bool? emailNotificationsEnabled,
    String? profileVisibility,
  }) async {
    isUpdating.value = true;
    updateError.value = null;
    updateSuccess.value = false;

    final result = await _repository.updateProfile(
      displayName: displayName,
      emailNotificationsEnabled: emailNotificationsEnabled,
      profileVisibility: profileVisibility,
    );
    switch (result) {
      case Success(:final value):
        profile.value = value;
        updateSuccess.value = true;
      case Failure(:final message):
        updateError.value = message;
    }

    isUpdating.value = false;
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
    stats.value = const ProfileStats(activeListings: 0, itemsSold: 0);
  }

  void dispose() {
    profile.dispose();
    isLoading.dispose();
    error.dispose();
    isUpdating.dispose();
    updateError.dispose();
    updateSuccess.dispose();
    stats.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
