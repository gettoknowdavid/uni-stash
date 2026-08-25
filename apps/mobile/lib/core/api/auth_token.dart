import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helpers for reading / writing the JWT access token stored in
/// [FlutterSecureStorage].  Used by [_AuthInterceptor] and by the rest of
/// the app (e.g. login / logout flows).
class AuthToken {
  AuthToken._();

  static const _key = 'access_token';

  static Future<String?> read(FlutterSecureStorage storage) =>
      storage.read(key: _key);

  static Future<void> write(FlutterSecureStorage storage, String token) =>
      storage.write(key: _key, value: token);

  static Future<void> clear(FlutterSecureStorage storage) =>
      storage.delete(key: _key);
}
