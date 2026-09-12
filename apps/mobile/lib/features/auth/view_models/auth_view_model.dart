import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
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
      configureAuthenticatedScope();
      batch(() {
        _status.value = .authenticated;
        _user.value = credentials.user;
      });
    });
    unauthenticate = action0<void>(() async {
      await _clearTokens();
      await tearDownAuthenticatedScope();
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

  /// Whether the signed-in user's email is verified (false while signed out).
  ///
  /// Mirrors `User.emailVerified`, kept as a dedicated derived signal so
  /// router code can react to a verification change even when the auth
  /// status itself doesn't move (e.g. a successful OTP submit while staying
  /// signed in).
  late final ReadonlySignal<bool> verified = computed(
    () => _user.value?.emailVerified ?? false,
  );

  /// Combines every auth fact the router's redirect reads into one signal.
  ///
  /// GoRouter's `refreshListenable` subscribes to this — instead of just
  /// [status] — so a verification-state change also re-runs the redirect
  /// (an unverified session is bounced to `/verify`; a session that just
  /// verified is let through to the shell).
  late final ReadonlySignal<Object?> routerRefresh = computed(
    () => (_status.value, verified.value),
  );

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

  /// Disposes the signals owned by this instance.
  ///
  /// AuthViewModel is registered as an app-lifetime singleton, so this is
  /// never called during normal operation — it exists so the type matches
  /// the disposal contract of the page-scoped view models and so tests that
  /// construct an instance directly can clean it up.
  void dispose() {
    routerRefresh.dispose();
    verified.dispose();
    _status.dispose();
    _user.dispose();
  }
}
