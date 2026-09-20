import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_api.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// Profile stats: real counts fetched from the listings API.
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
  ProfileRepositoryImpl(this._authClient, this._listingsClient, this._logger);

  final AuthApiClient _authClient;
  final ListingsApiClient _listingsClient;
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
      // We can't get a total count from the paginated API, so we fetch up
      // to 100 and count — good enough for profile stats.
      final activeAll = await _listingsClient.getList(
        sellerId: userId,
        status: ListingStatus.active,
        limit: 100,
      );
      final activeCount = activeAll.data?.listings.length ?? 0;

      // Fetch sold listings count
      final soldResponse = await _listingsClient.getList(
        sellerId: userId,
        status: ListingStatus.sold,
        limit: 100,
      );
      final soldCount = soldResponse.data?.listings.length ?? 0;

      return Result.success(
        ProfileStats(
          activeListings: activeCount,
          itemsSold: soldCount,
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
