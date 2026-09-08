import 'package:logger/logger.dart';
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
  Future<Result<Listing>> create(CreateListingRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ListingDetailResponse?>> getListing(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ListListingsResponse>> list(ListListingsQuery query) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Listing>> markAsSold(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Listing>> reserve(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Listing>> unreserve(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Listing>> update(String id, UpdateListingRequest request) {
    throw UnimplementedError();
  }
}
