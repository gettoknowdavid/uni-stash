import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';

/// Profile stats: exact counts from GET /auth/me/stats.
class ProfileStats {
  const ProfileStats({
    required this.activeListings,
    required this.itemsSold,
    this.saved = 0,
  });

  final int activeListings;
  final int itemsSold;
  final int saved;
}

/// Abstraction over the profile data source.
abstract interface class ProfileRepository {
  /// Fetches the signed-in user's profile (DB-fresh, not the cached
  /// session user held by AuthViewModel).
  Future<Result<User>> getProfile();

  /// Fetches the user's listing stats (active count, sold count).
  Future<Result<ProfileStats>> getStats(String userId);

  /// Updates the user's profile (display_name).
  Future<Result<User>> updateProfile({String? displayName});
}

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._authClient, this._logger);

  final AuthApiClient _authClient;
  final Logger _logger;

  @override
  Future<Result<User>> getProfile() async {
    try {
      final response = await _authClient.me();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ProfileRepository] getProfile failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ProfileRepository] getProfile unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ProfileStats>> getStats(String userId) async {
    try {
      // The backend /auth/me/stats endpoint computes exact COUNT(*)s,
      // including the real saved-items count.
      final response = await _authClient.getProfileStats();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');

      return Result.success(
        ProfileStats(
          activeListings: data.activeListings,
          itemsSold: data.itemsSold,
          saved: data.saved,
        ),
      );
    } on DioException catch (e) {
      _logger.e('[ProfileRepository] getStats failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ProfileRepository] getStats unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<User>> updateProfile({String? displayName}) async {
    try {
      final response = await _authClient.updateProfile(
        UpdateProfileRequest(displayName: displayName),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ProfileRepository] updateProfile failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ProfileRepository] updateProfile unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
