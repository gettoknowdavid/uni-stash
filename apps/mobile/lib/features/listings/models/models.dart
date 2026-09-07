import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

enum ListingStatus { active, reserved, sold, deleted }

@JsonEnum()
enum Condition {
  @JsonValue('new')
  isNew,
  used,
  fair,
}

@freezed
abstract class Listing with _$Listing {
  const factory Listing({
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
  }) = _Listing;

  factory Listing.fromJson(Map<String, dynamic> json) =>
      _$ListingFromJson(json);
}

@freezed
abstract class Seller with _$Seller {
  const factory Seller({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
  }) = _Seller;

  factory Seller.fromJson(Map<String, dynamic> json) => _$SellerFromJson(json);
}

@freezed
abstract class Category with _$Category {
  const factory Category({
    required int id,
    required String slug,
    required String label,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);
}

@freezed
abstract class Image with _$Image {
  const factory Image({
    required String id,
    @JsonKey(name: 'object_key') required String objectKey,
    required int position,
  }) = _Image;

  factory Image.fromJson(Map<String, dynamic> json) => _$ImageFromJson(json);
}
