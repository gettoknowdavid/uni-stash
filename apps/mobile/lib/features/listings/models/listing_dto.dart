import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

part 'listing_dto.freezed.dart';
part 'listing_dto.g.dart';

@freezed
abstract class CreateListingRequest with _$CreateListingRequest {
  const factory CreateListingRequest({
    required String title,
    required Condition condition,
    @JsonKey(name: 'category_id') required int categoryId,
    double? price,
    String? description,
    @JsonKey(name: 'barter_request') String? barterRequest,
  }) = _CreateListingRequest;

  factory CreateListingRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateListingRequestFromJson(json);
}

@freezed
abstract class UpdateListingRequest with _$UpdateListingRequest {
  const factory UpdateListingRequest({
    String? title,
    Condition? condition,
    @JsonKey(name: 'category_id') int? categoryId,
    double? price,
    String? description,
    @JsonKey(name: 'barter_request') String? barterRequest,
  }) = _UpdateListingRequest;

  factory UpdateListingRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateListingRequestFromJson(json);
}

@freezed
abstract class ListListingsQuery with _$ListListingsQuery {
  const factory ListListingsQuery({
    String? q,
    @JsonKey(name: 'category_id') int? categoryId,
    @JsonKey(name: 'min_price') double? minPrice,
    @JsonKey(name: 'max_price') double? maxPrice,
    ListingStatus? status,
    String? cursor,
    @Default(50) int limit,
  }) = _ListListingsQuery;

  factory ListListingsQuery.fromJson(Map<String, dynamic> json) =>
      _$ListListingsQueryFromJson(json);
}

@freezed
abstract class ListListingsResponse with _$ListListingsResponse {
  const factory ListListingsResponse({
    required List<Listing> listings,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _ListListingsResponse;

  factory ListListingsResponse.fromJson(Map<String, dynamic> json) =>
      _$ListListingsResponseFromJson(json);
}

/// Response of `GET /api/v1/categories`: all categories ordered by
/// `sort_order`.
@freezed
abstract class ListCategoriesResponse with _$ListCategoriesResponse {
  const factory ListCategoriesResponse({
    required List<Category> categories,
  }) = _ListCategoriesResponse;

  factory ListCategoriesResponse.fromJson(Map<String, dynamic> json) =>
      _$ListCategoriesResponseFromJson(json);
}

@freezed
abstract class ListingDetailResponse with _$ListingDetailResponse {
  const factory ListingDetailResponse({
    required String id,
    required String title,
    required String description,
    required Condition condition,
    required ListingStatus status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    required Seller seller,
    required Category category,
    required List<Image> images,
    double? price,
  }) = _ListingDetailResponse;

  factory ListingDetailResponse.fromJson(Map<String, dynamic> json) =>
      _$ListingDetailResponseFromJson(json);
}
