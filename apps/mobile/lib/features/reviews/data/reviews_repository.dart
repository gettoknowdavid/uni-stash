import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/reviews/data/reviews_api.dart';
import 'package:uni_stash_mobile/features/reviews/models/reviews_models.dart';

/// Abstraction over the reviews data source.
abstract interface class ReviewsRepository {
  /// Rates the counterpart of [saleId]. Fails with the server's message
  /// when the caller wasn't part of the sale (403) or already reviewed
  /// it (409).
  Future<Result<Review>> create(String saleId, CreateReviewRequest request);

  /// A user's rating wall + summary.
  Future<Result<UserReviewsResponse>> forUser(String userId);

  /// The caller's existing review for [saleId] (null when unreviewed).
  Future<Result<Review?>> myReviewForSale(String saleId);
}

class ReviewsRepositoryImpl implements ReviewsRepository {
  ReviewsRepositoryImpl(this._client, this._logger);

  final ReviewsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<Review>> create(
    String saleId,
    CreateReviewRequest request,
  ) async {
    try {
      final response = await _client.create(saleId, request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ReviewsRepository] create failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReviewsRepository] create unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<UserReviewsResponse>> forUser(String userId) async {
    try {
      final response = await _client.forUser(userId);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ReviewsRepository] forUser failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ReviewsRepository] forUser unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<Review?>> myReviewForSale(String saleId) async {
    try {
      final response = await _client.myReviewForSale(saleId);
      if (!response.status) return Result.failure(response.message);
      return Result.success(response.data);
    } on DioException catch (e) {
      _logger.e('[ReviewsRepository] myReviewForSale failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e(
        '[ReviewsRepository] myReviewForSale unexpected error',
        error: e,
      );
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
