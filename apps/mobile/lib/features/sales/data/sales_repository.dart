import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/sales/data/sales_api.dart';
import 'package:uni_stash_mobile/features/sales/models/sales_dto.dart';

/// Repository for sale history (My Purchases / My Sales).
abstract interface class SalesRepository {
  Future<Result<SalesListResponse>> myPurchases({String? cursor, int limit});

  Future<Result<SalesListResponse>> mySales({String? cursor, int limit});
}

class SalesRepositoryImpl implements SalesRepository {
  SalesRepositoryImpl(this._client, this._logger);

  final SalesApiClient _client;
  final Logger _logger;

  @override
  Future<Result<SalesListResponse>> myPurchases({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _client.myPurchases(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SalesRepository] myPurchases failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SalesRepository] myPurchases unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<SalesListResponse>> mySales({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _client.mySales(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SalesRepository] mySales failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SalesRepository] mySales unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
