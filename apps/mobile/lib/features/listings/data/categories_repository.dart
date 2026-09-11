import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_api.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';

abstract interface class CategoriesRepository {
  Future<Result<ListCategoriesResponse>> list();
}

class CategoriesRepositoryImpl implements CategoriesRepository {
  CategoriesRepositoryImpl(this._client, this._logger);

  final CategoriesApiClient _client;
  final Logger _logger;

  @override
  Future<Result<ListCategoriesResponse>> list() async {
    try {
      final response = await _client.getCategories();
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[CategoriesRepository] list failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[CategoriesRepository] list unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
