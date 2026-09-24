import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_api.dart';

/// Server-backed saved (bookmarked) listings — persisted per user account
/// so bookmarks sync across devices and survive reinstalls.
///
/// Save/unsave are idempotent on the backend, so retries and double-taps
/// are safe.
abstract interface class SavedItemsRepository {
  /// Listing ids the user saved, newest first. Cursor pagination is
  /// available for future scaling; the profile page fetches one page.
  Future<Result<List<String>>> load({String? cursor, int limit});

  /// Saves [listingId]. Idempotent.
  Future<Result<void>> save(String listingId);

  /// Unsaves [listingId]. Idempotent.
  Future<Result<void>> remove(String listingId);

  /// Whether [listingId] is saved by the signed-in user.
  Future<Result<bool>> isSaved(String listingId);

  /// Toggles [listingId]; returns the new saved state.
  Future<Result<bool>> toggle(String listingId);
}

class SavedItemsRepositoryImpl implements SavedItemsRepository {
  SavedItemsRepositoryImpl(this._client, this._logger);

  final SavedItemsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<List<String>>> load({String? cursor, int limit = 100}) async {
    try {
      final response = await _client.list(cursor: cursor, limit: limit);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(
        data.items.map((item) => item.listingId).toList(growable: false),
      );
    } on DioException catch (e) {
      _logger.e('[SavedItemsRepository] load failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SavedItemsRepository] load unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> save(String listingId) async {
    try {
      final response = await _client.save(listingId);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[SavedItemsRepository] save failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SavedItemsRepository] save unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> remove(String listingId) async {
    try {
      // DELETE returns 204 No Content — no ApiResponse body to decode.
      final response = await _client.unsave(listingId);
      final code = response.response.statusCode ?? 0;
      if (code >= 200 && code < 300) return const Result.success(null);
      return Result.failure('Failed to remove saved item ($code)');
    } on DioException catch (e) {
      _logger.e('[SavedItemsRepository] remove failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SavedItemsRepository] remove unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<bool>> isSaved(String listingId) async {
    try {
      final response = await _client.status(listingId);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data.saved);
    } on DioException catch (e) {
      _logger.e('[SavedItemsRepository] isSaved failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[SavedItemsRepository] isSaved unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<bool>> toggle(String listingId) async {
    final saved = await isSaved(listingId);
    switch (saved) {
      case Success(:final value):
        final result = value ? await remove(listingId) : await save(listingId);
        return switch (result) {
          Success() => Result.success(!value),
          Failure(:final message) => Result.failure(message),
        };
      case Failure(:final message):
        return Result.failure(message);
    }
  }
}
