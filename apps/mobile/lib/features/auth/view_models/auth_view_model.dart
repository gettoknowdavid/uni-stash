import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

/// Represents the authentication status of the user.
enum AuthStatus { loading, authenticated, unauthenticated }

const String _accessTokenKey = 'access_token';
const String _refreshTokenKey = 'refresh_token';

class AuthViewModel {
  AuthViewModel(this._repository, this._storage) {
    authenticate = action1<UserCredentials, void>((credentials) async {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: credentials.accessToken),
        _storage.write(key: _refreshTokenKey, value: credentials.refreshToken),
      ]);
      batch(() {
        _status.value = .authenticated;
        _user.value = credentials.user;
      });
    });
    unauthenticate = action0<void>(() async {
      await _clearTokens();
      batch(() {
        _user.value = null;
        _status.value = .unauthenticated;
      });
    });
  }

  final IAuthRepository _repository;
  final FlutterSecureStorage _storage;

  final Signal<AuthStatus> _status = signal(.loading);
  ReadonlySignal<AuthStatus> get status => _status;

  final Signal<User?> _user = signal(null);
  ReadonlySignal<User?> get user => _user;

  late final void Function(UserCredentials) authenticate;
  late final void Function() unauthenticate;

  /// Call once at app startup, before runApp, so the router's initial
  /// redirect decision is correct on first paint.
  Future<void> bootstrap() async {
    final token = await _storage.read(key: _accessTokenKey);
    if (token == null || token.isEmpty) {
      _status.value = AuthStatus.unauthenticated;
      return;
    }

    final profile = await _repository.me();
    await profile.fold(
      (user) {
        batch(() {
          _user.value = user;
          _status.value = .authenticated;
        });
      },
      (error) async {
        await _clearTokens();
        _status.value = .unauthenticated;
      },
    );
  }

  /// Reads the access token from the secure storage.
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  /// Reads the refresh token from the secure storage.
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> _clearTokens() {
    return Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }
}
