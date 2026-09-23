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
