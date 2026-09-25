import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

part 'saved_items_dto.freezed.dart';
part 'saved_items_dto.g.dart';

/// Saved-items list response. The backend hydrates each saved bookmark
/// with the full listing summary (title, price, status, photos), so the
/// client renders the grid from this single response — no per-id detail
/// fetches.
@freezed
abstract class SavedItemsListResponse with _$SavedItemsListResponse {
  const factory SavedItemsListResponse({
    required List<ListingSummary> listings,
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
