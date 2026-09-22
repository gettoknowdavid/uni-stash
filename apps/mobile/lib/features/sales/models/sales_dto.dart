import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/features/sales/models/models.dart';

part 'sales_dto.freezed.dart';
part 'sales_dto.g.dart';

@freezed
abstract class SalesListResponse with _$SalesListResponse {
  const factory SalesListResponse({
    required List<Sale> sales,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _SalesListResponse;

  factory SalesListResponse.fromJson(Map<String, dynamic> json) =>
      _$SalesListResponseFromJson(json);
}
