import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

@freezed
abstract class Sale with _$Sale {
  const factory Sale({
    required String id,
    @JsonKey(name: 'listing_id') required String listingId,
    /// Null for walk-up sales (no reservation to capture the buyer).
    @JsonKey(name: 'buyer_id') String? buyerId,
    @JsonKey(name: 'seller_id') required String sellerId,
    @JsonKey(name: 'listing_title') required String listingTitle,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    double? price,
    String? currency,
    @JsonKey(name: 'barter_request') String? barterRequest,
  }) = _Sale;

  factory Sale.fromJson(Map<String, dynamic> json) => _$SaleFromJson(json);
}
