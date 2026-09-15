import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_api.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

abstract interface class ListingsRepository {
  Future<Result<Listing>> create(CreateListingRequest request);
  Future<Result<Listing>> update(String id, UpdateListingRequest request);
  Future<Result<void>> delete(String id);
  Future<Result<ListingDetailResponse?>> getListing(String id);
  Future<Result<ListListingsResponse>> list(ListListingsQuery query);
  Future<Result<Listing>> reserve(String id);
  Future<Result<Listing>> unreserve(String id);
  Future<Result<Listing>> markAsSold(String id);
}

class ListingsRepositoryImpl implements ListingsRepository {
  ListingsRepositoryImpl(this._client, this._logger);

  final ListingsApiClient _client;
  final Logger _logger;

  @override
  Future<Result<Listing>> create(CreateListingRequest request) async {
    try {
      final response = await _client.create(request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] create failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] create unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<Listing>> update(
    String id,
    UpdateListingRequest request,
  ) async {
    try {
      final response = await _client.update(id, request);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] update failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] update unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final response = await _client.delete(id);
      if (!response.status) return Result.failure(response.message);
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] delete failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] delete unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ListingDetailResponse?>> getListing(String id) async {
    try {
      final response = await _client.getListing(id);
      if (!response.status) return Result.failure(response.message);
      return Result.success(response.data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] getListing failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] getListing unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<ListListingsResponse>> list(ListListingsQuery query) async {
    try {
      final response = await _client.getList(
        q: query.q,
        categoryId: query.categoryId,
        minPrice: query.minPrice,
        maxPrice: query.maxPrice,
        status: query.status,
        cursor: query.cursor,
        limit: query.limit,
      );
      di<Logger>().w(response.data);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] list failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] list unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<Listing>> reserve(String id) async {
    try {
      final response = await _client.reserve(id);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] reserve failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] reserve unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<Listing>> unreserve(String id) async {
    try {
      final response = await _client.unreserve(id);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] unreserve failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] unreserve unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<Listing>> markAsSold(String id) async {
    try {
      final response = await _client.markSold(id);
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ListingsRepository] markAsSold failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ListingsRepository] markAsSold unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }
}
