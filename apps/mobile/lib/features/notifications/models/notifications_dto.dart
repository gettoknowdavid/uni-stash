import 'package:freezed_annotation/freezed_annotation.dart';

part 'notifications_dto.freezed.dart';
part 'notifications_dto.g.dart';

/// Body for `POST /api/v1/notifications/register-device` (guide 7.9).
///
/// Idempotent server-side: re-registering the same token updates the
/// platform field.
@freezed
abstract class RegisterDeviceRequest with _$RegisterDeviceRequest {
  const factory RegisterDeviceRequest({
    /// The device push token (APNs / FCM / Beams).
    required String token,

    /// One of `ios`, `android`, `web` (validated server-side).
    required String platform,
  }) = _RegisterDeviceRequest;

  factory RegisterDeviceRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterDeviceRequestFromJson(json);
}

/// One in-app notification in the inbox.
@freezed
abstract class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    @JsonKey(name: 'recipient_id') required String recipientId,

    /// Dotted type tag mapped to an icon + route
    /// (`chat.message`, `sale.completed`, `review.received`).
    @JsonKey(name: 'type') required String type,
    required String title,
    required String body,

    @JsonKey(name: 'created_at') required DateTime createdAt,

    /// Deep-link payload (`chat_id`, `listing_id`, ...) or null.
    Map<String, dynamic>? data,

    @JsonKey(name: 'read_at') DateTime? readAt,
  }) = _AppNotification;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);
}

@freezed
abstract class InboxResponse with _$InboxResponse {
  const factory InboxResponse({
    required List<AppNotification> notifications,
    @JsonKey(name: 'unread_count') required int unreadCount,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _InboxResponse;

  factory InboxResponse.fromJson(Map<String, dynamic> json) =>
      _$InboxResponseFromJson(json);
}
