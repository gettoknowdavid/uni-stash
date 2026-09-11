import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@JsonEnum()
enum Condition {
  @JsonValue('new')
  isNew,
  used,
  fair;

  String get message => switch (this) {
    isNew => 'NEW',
    used => 'USED',
    fair => 'FAIR',
  };
}

@freezed
abstract class Category with _$Category {
  const factory Category({
    required int id,
    required String slug,
    required String label,
  }) = _Category;

  factory Category.fake({int id = 1}) {
    return Category(id: id, slug: 'category-$id', label: 'Category $id');
  }

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);

  static List<Category> fakeList({int count = 4}) {
    return List.generate(count, (index) => Category.fake(id: index + 1));
  }
}

@freezed
abstract class Image with _$Image {
  const factory Image({
    required String id,
    @JsonKey(name: 'object_key') required String objectKey,
    required int position,
    // Local-only preview path for freshly picked photos that have not been
    // uploaded yet. Never serialized to/from JSON.
    @JsonKey(includeFromJson: false, includeToJson: false) String? localPath,
  }) = _Image;

  factory Image.fromJson(Map<String, dynamic> json) => _$ImageFromJson(json);
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

enum ListingStatus { active, reserved, sold, deleted }

@freezed
abstract class Seller with _$Seller {
  const factory Seller({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
  }) = _Seller;

  factory Seller.fromJson(Map<String, dynamic> json) => _$SellerFromJson(json);
}
