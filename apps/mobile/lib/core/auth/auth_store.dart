import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uni_stash_mobile/core/auth/auth_status.dart';

const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

Future<void> bootstrapAuth(FlutterSecureStorage storage) async {
  final token = await storage.read(key: _accessTokenKey);
  authStatus.value = (token != null && token.isNotEmpty)
      ? .authenticated
      : .unauthenticated;
}

Future<void> markAuthenticated(
  FlutterSecureStorage storage, {
  required String accessToken,
  required String refreshToken,
}) async {
  await Future.wait([
    storage.write(key: _accessTokenKey, value: accessToken),
    storage.write(key: _refreshTokenKey, value: refreshToken),
  ]);
  authStatus.value = .authenticated;
}

Future<void> markUnauthenticated(FlutterSecureStorage storage) async {
  await Future.wait([
    storage.delete(key: _accessTokenKey),
    storage.delete(key: _refreshTokenKey),
  ]);
  authStatus.value = .unauthenticated;
}

Future<String?> readAccessToken(FlutterSecureStorage storage) {
  return storage.read(key: _accessTokenKey);
}

Future<String?> readRefreshToken(FlutterSecureStorage storage) {
  return storage.read(key: _refreshTokenKey);
}
