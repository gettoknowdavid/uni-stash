import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/profile/data/users_api.dart';
import 'package:uni_stash_mobile/features/profile/models/public_profile.dart';

/// Public user profile data source.
abstract interface class UsersRepository {
  Future<Result<PublicProfile>> getProfile(String userId);

  Future<Result<ListListingsResponse>> getUserListings(
    String userId, {
    String? cursor,
    int limit,
  });
}

class UsersRepositoryImpl implements UsersRepository {
  UsersRepositoryImpl(this._api, this._logger);

  final UsersApiClient _api;
  final Logger _logger;

  @override
  Future<Result<PublicProfile>> getProfile(String userId) async {
    try {
      final response = await _api.getProfile(userId);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[UsersRepository] getProfile failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[UsersRepository] getProfile unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ListListingsResponse>> getUserListings(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _api.getUserListings(
        userId,
        cursor: cursor,
        limit: limit,
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[UsersRepository] getUserListings failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[UsersRepository] getUserListings unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}

typedef ListingSummaryRef = ListingSummary;
