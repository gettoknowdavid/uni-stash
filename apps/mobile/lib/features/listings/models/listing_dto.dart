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
    String? dscription,
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
    String? dscription,
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

@freezed
abstract class ListingResponse with _$ListingResponse {
  const factory ListingResponse({
    required String id,
    @JsonKey(name: 'seller_id') required String sellerId,
    @JsonKey(name: 'category_id') required int categoryId,
    required String title,
    required String description,
    required Condition condition,
    required ListingStatus status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    double? price,
    @JsonKey(name: 'reserved_by') String? reservedBy,
    @JsonKey(name: 'reserved_at') DateTime? reservedAt,
  }) = _ListingResponse;

  factory ListingResponse.fromJson(Map<String, dynamic> json) =>
      _$ListingResponseFromJson(json);
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
