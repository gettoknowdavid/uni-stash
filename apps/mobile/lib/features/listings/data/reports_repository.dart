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

  /// The signed-in user's own reports, newest first.
  Future<Result<List<ReportResponse>>> mine({String? cursor, int limit});

  /// Updates the reason on one of the user's open reports.
  Future<Result<ReportResponse>> update(String reportId, {String? reason});

  /// Withdraws one of the user's open reports. Fails with the server's
  /// message when the report is already under moderation.
  Future<Result<void>> delete(String reportId);
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

  @override
  Future<Result<List<ReportResponse>>> mine({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await _client.mine(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.reports);
    } on DioException catch (e) {
      _logger.e('[ReportsRepository] mine failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReportsRepository] mine unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ReportResponse>> update(
    String reportId, {
    String? reason,
  }) async {
    try {
      final response = await _client.update(
        reportId,
        CreateReportRequest(reason: reason),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ReportsRepository] update failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReportsRepository] update unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> delete(String reportId) async {
    try {
      final response = await _client.delete(reportId);
      final code = response.response.statusCode ?? 0;
      if (code >= 200 && code < 300) return const Result.success(null);
      return Result.failure('Failed to withdraw report ($code)');
    } on DioException catch (e) {
      _logger.e('[ReportsRepository] delete failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReportsRepository] delete unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
