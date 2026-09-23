import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/notifications/models/notifications_dto.dart';

part 'notifications_api.g.dart';

@RestApi()
abstract class NotificationsApiClient {
  factory NotificationsApiClient(Dio dio, {String? baseUrl}) =
      _NotificationsApiClient;

  /// Registers the device's push token for the signed-in user
  /// (authenticated; idempotent on the backend).
  @POST('/api/v1/notifications/register-device')
  Future<ApiResponse<void>> registerDevice(
    @Body() RegisterDeviceRequest request,
  );
}
