import 'package:freezed_annotation/freezed_annotation.dart';

part 'saved_items_dto.freezed.dart';
part 'saved_items_dto.g.dart';

@freezed
abstract class SavedItem with _$SavedItem {
  const factory SavedItem({
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'saved_at') required DateTime savedAt,
  }) = _SavedItem;

  factory SavedItem.fromJson(Map<String, dynamic> json) =>
      _$SavedItemFromJson(json);
}

@freezed
abstract class SavedItemsListResponse with _$SavedItemsListResponse {
  const factory SavedItemsListResponse({
    required List<SavedItem> items,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _SavedItemsListResponse;

  factory SavedItemsListResponse.fromJson(Map<String, dynamic> json) =>
      _$SavedItemsListResponseFromJson(json);
}

@freezed
abstract class SavedItemStatusResponse with _$SavedItemStatusResponse {
  const factory SavedItemStatusResponse({required bool saved}) =
      _SavedItemStatusResponse;

  factory SavedItemStatusResponse.fromJson(Map<String, dynamic> json) =>
      _$SavedItemStatusResponseFromJson(json);
}
