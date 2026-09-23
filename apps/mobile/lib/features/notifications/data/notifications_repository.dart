import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/features/notifications/data/notifications_api.dart';
import 'package:uni_stash_mobile/features/notifications/models/notifications_dto.dart';

/// Fire-and-forget device registration (guide 7.9). Called once after
/// login; failures never block or fail the login flow.
class NotificationsRepository {
  NotificationsRepository(this._client, this._logger);

  final NotificationsApiClient _client;
  final Logger _logger;

  /// Registers [token] for the current user on [platform]
  /// (`ios` / `android` / `web`). Swallows every error — push
  /// registration is best-effort.
  Future<void> registerDevice(String token, String platform) async {
    try {
      await _client.registerDevice(
        RegisterDeviceRequest(token: token, platform: platform),
      );
    } on Object catch (e) {
      // Best-effort: don't block login if registration fails.
      _logger.w('[Notifications] Device registration failed', error: e);
    }
  }
}
