import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/blocks/data/blocks_api.dart';
import 'package:uni_stash_mobile/features/blocks/models/models.dart';

/// Blocks feature data source. The list endpoint is typed; block/unblock
/// tunnel through the same client and are surfaced as plain [Result]s.
abstract interface class BlocksRepository {
  Future<Result<List<BlockedUser>>> listBlocked();

  /// Returns true on success (including idempotent re-blocks).
  Future<Result<void>> block(String userId);

  Future<Result<void>> unblock(String userId);
}

class BlocksRepositoryImpl implements BlocksRepository {
  BlocksRepositoryImpl(this._api, this._logger);

  final BlocksApiClient _api;
  final Logger _logger;

  @override
  Future<Result<List<BlockedUser>>> listBlocked() async {
    try {
      final response = await _api.listBlocked();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.blockedUsers);
    } on DioException catch (e) {
      _logger.e('[BlocksRepository] listBlocked failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[BlocksRepository] listBlocked unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> block(String userId) async {
    try {
      final response = await _api.blockUser(userId);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[BlocksRepository] block failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[BlocksRepository] block unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> unblock(String userId) async {
    try {
      await _api.unblockUser(userId);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[BlocksRepository] unblock failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[BlocksRepository] unblock unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
