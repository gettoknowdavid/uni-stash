import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/listings/data/reports_api.dart';

/// Abstraction over the reports data source.
abstract interface class ReportsRepository {
  /// Flags [listingId] for moderation with an optional [reason].
  /// Idempotent server-side: re-reporting the same listing succeeds
  /// without creating a duplicate.
  Future<Result<ReportResponse>> create(String listingId, {String? reason});
}

class ReportsRepositoryImpl implements ReportsRepository {
  ReportsRepositoryImpl(this._client, this._logger);

  final ReportsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<ReportResponse>> create(
    String listingId, {
    String? reason,
  }) async {
    try {
      final response = await _client.create(
        listingId,
        CreateReportRequest(reason: reason),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ReportsRepository] create failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReportsRepository] create unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
