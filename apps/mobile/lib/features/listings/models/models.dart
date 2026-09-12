import 'package:freezed_annotation/freezed_annotation.dart' as fda;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

String _groupThousands(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return n < 0 ? '-$buffer' : buffer.toString();
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

// ---------------------------------------------------------------------------
// Money — integer minor units (kobo) + ISO 4217 currency.
//
// Money is NEVER a double anywhere in the app. All amounts are exact i64
// minor units (kobo for NGN), mirroring the backend's `core::money`.
// Wire format: {"amount_minor": 150000, "currency": "NGN"}.
// ---------------------------------------------------------------------------

@fda.JsonEnum()
enum Currency {
  @fda.JsonValue('NGN')
  ngn('NGN', '₦', 'Naira'),
  @fda.JsonValue('USD')
  usd('USD', r'$', 'US Dollar'),
  @fda.JsonValue('EUR')
  eur('EUR', '€', 'Euro'),
  @fda.JsonValue('GBP')
  gbp('GBP', '£', 'Pound Sterling');

  const Currency(this.code, this.symbol, this.label);

  /// 10^exponent — all supported currencies are 2-decimal.
  static const int _scale = 100;
  final String code;
  final String symbol;

  final String label;
  int get scale => _scale;

  static Currency fromCode(String code) => Currency.values.firstWhere(
    (c) => c.code == code.toUpperCase(),
    orElse: () => Currency.ngn,
  );
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
    Money? price,
    @JsonKey(name: 'reserved_by') String? reservedBy,
    @JsonKey(name: 'reserved_at') DateTime? reservedAt,
    @JsonKey(name: 'barter_request') String? barterRequest,
  }) = _Listing;

  factory Listing.fromJson(Map<String, dynamic> json) =>
      _$ListingFromJson(json);
}

enum ListingStatus { active, reserved, sold, deleted }

@immutable
@fda.JsonSerializable()
class Money {
  const Money({required this.amountMinor, this.currency = Currency.ngn});

  factory Money.fromJson(Map<String, dynamic> json) => _$MoneyFromJson(json);

  /// Amount in the currency's smallest unit (kobo/cents). Never negative.
  @fda.JsonKey(name: 'amount_minor')
  final int amountMinor;
  @fda.JsonKey()
  final Currency currency;

  /// `₦1,500.00` — assembled from integers, never a double.
  String get display =>
      '${currency.symbol}${_groupThousands(majorPart)}.'
      '${minorPart.toString().padLeft(2, '0')}';

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  /// Major-unit part (integer division; drops the minor part).
  int get majorPart => amountMinor ~/ currency.scale;

  /// Minor-unit remainder (0..99 for 2-exponent currencies).
  int get minorPart => amountMinor % currency.scale;

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  Money checkedAdd(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'currency mismatch: ${currency.code} vs ${other.currency.code}',
      );
    }
    return Money(
      amountMinor: amountMinor + other.amountMinor,
      currency: currency,
    );
  }

  Money checkedSub(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'currency mismatch: ${currency.code} vs ${other.currency.code}',
      );
    }
    if (other.amountMinor > amountMinor) {
      throw ArgumentError('insufficient amount');
    }
    return Money(
      amountMinor: amountMinor - other.amountMinor,
      currency: currency,
    );
  }

  Map<String, dynamic> toJson() => _$MoneyToJson(this);

  @override
  String toString() => display;

  /// ₦1,500.00 => 150000 kobo.
  static Money fromMajor(int major, [Currency currency = Currency.ngn]) =>
      Money(amountMinor: major * 100, currency: currency);
}

@freezed
abstract class Seller with _$Seller {
  const factory Seller({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
  }) = _Seller;

  factory Seller.fromJson(Map<String, dynamic> json) => _$SellerFromJson(json);
}
