/// Native push-token access (guide 7.9).
///
/// Placeholder until a push SDK (Pusher Beams / firebase_messaging) is
/// configured: [getToken] resolves `null`, so device registration is
/// skipped while the rest of the pipeline — API client, repository, the
/// post-login hook in `AuthViewModel` and the deep-link handler in
/// `push_handler.dart` — is already wired end-to-end.
///
/// When the SDK lands, implement [getToken] (and the foreground-message
/// listener, see `push_handler.dart`) and nothing else changes.
abstract final class PushNotifications {
  /// The device's push token, or null when native push isn't configured.
  static Future<String?> getToken() async => null;
}
