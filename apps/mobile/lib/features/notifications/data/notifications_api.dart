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

  /// The caller's in-app inbox, newest first, cursor-paginated.
  @GET('/api/v1/notifications')
  Future<ApiResponse<InboxResponse>> listInbox({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  /// Marks one notification read.
  @POST('/api/v1/notifications/{id}/read')
  Future<ApiResponse<void>> markRead(@Path('id') String id);

  /// Marks every unread notification read; returns rows changed.
  @POST('/api/v1/notifications/read-all')
  Future<ApiResponse<int>> markAllRead();

  /// Deletes one notification (204 on success).
  @DELETE('/api/v1/notifications/{id}')
  Future<HttpResponse<void>> deleteNotification(@Path('id') String id);
}
