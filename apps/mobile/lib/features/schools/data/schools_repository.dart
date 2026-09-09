import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_api.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';

abstract interface class SchoolsRepository {
  Future<Result<ListSchoolsResponse>> list(ListSchoolsQuery query);
  Future<Result<School>> getSchool(String id);
}

class SchoolsRepositoryImpl implements SchoolsRepository {
  SchoolsRepositoryImpl(this._client, this._logger);

  final SchoolsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<ListSchoolsResponse>> list(ListSchoolsQuery query) async {
    try {
      final response = await _client.getList(
        q: query.q,
        cursor: query.cursor,
        limit: query.limit,
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SchoolsRepository] list failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SchoolsRepository] list unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<School>> getSchool(String id) async {
    try {
      final response = await _client.getSchool(id);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[SchoolsRepository] getSchool failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SchoolsRepository] getSchool unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
