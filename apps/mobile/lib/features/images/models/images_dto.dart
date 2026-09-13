import 'package:freezed_annotation/freezed_annotation.dart';

part 'images_dto.freezed.dart';
part 'images_dto.g.dart';

/// Content types the backend accepts for listing photos
/// (`apps/api/src/features/images/dtos.rs` ALLOWED_CONTENT_TYPES).
enum ImageContentType {
  jpeg('image/jpeg'),
  png('image/png'),
  webp('image/webp');

  const ImageContentType(this.mime);

  /// MIME type sent to `POST /api/v1/images/presign`.
  final String mime;

  /// Best-effort sniffing from a picked file's extension; falls back to jpeg.
  static ImageContentType fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return ImageContentType.png;
    if (lower.endsWith('.webp')) return ImageContentType.webp;
    return ImageContentType.jpeg;
  }
}

/// Body of `POST /api/v1/images/presign`.
@freezed
abstract class PresignRequest with _$PresignRequest {
  const factory PresignRequest({
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'content_type') required String contentType,
  }) = _PresignRequest;

  factory PresignRequest.fromJson(Map<String, dynamic> json) =>
      _$PresignRequestFromJson(json);
}

/// Response of `POST /api/v1/images/presign`: a short-lived direct-upload URL
/// plus the object key that must be echoed back in the confirm call.
@freezed
abstract class PresignResponse with _$PresignResponse {
  const factory PresignResponse({
    @JsonKey(name: 'upload_url') required String uploadUrl,
    @JsonKey(name: 'object_key') required String objectKey,
    required int position,
  }) = _PresignResponse;

  factory PresignResponse.fromJson(Map<String, dynamic> json) =>
      _$PresignResponseFromJson(json);
}

/// Body of `POST /api/v1/images/confirm`.
@freezed
abstract class ConfirmRequest with _$ConfirmRequest {
  const factory ConfirmRequest({
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'object_key') required String objectKey,
  }) = _ConfirmRequest;

  factory ConfirmRequest.fromJson(Map<String, dynamic> json) =>
      _$ConfirmRequestFromJson(json);
}

/// Response of `POST /api/v1/images/confirm` — the registered image row.
@freezed
abstract class ConfirmResponse with _$ConfirmResponse {
  const factory ConfirmResponse({
    required String id,
    @JsonKey(name: 'listing_id') required String listingId,
    @JsonKey(name: 'object_key') required String objectKey,
    required int position,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ConfirmResponse;

  factory ConfirmResponse.fromJson(Map<String, dynamic> json) =>
      _$ConfirmResponseFromJson(json);
}
