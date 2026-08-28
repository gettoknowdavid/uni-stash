import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/auth/auth_store.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';

/// The observable state of the auth feature.
enum AuthActionState { idle, loading, success, error }

/// Centralised, signal-driven state container for authentication.
///
/// Exposes immutable [ReadonlySignal] views so the UI can subscribe
/// without being able to mutate state directly.
class AuthNotifier {
  AuthNotifier({
    required IAuthRepository repository,
    required FlutterSecureStorage storage,
    Logger? logger,
  })  : _repository = repository,
        _storage = storage,
        _logger = logger ?? Logger();

  final IAuthRepository _repository;
  final FlutterSecureStorage _storage;
  final Logger _logger;

  // ── Observable state ──────────────────────────────────────────

  /// Current action state (idle → loading → success/error → idle).
  final Signal<AuthActionState> _actionState =
      signal(AuthActionState.idle);
  ReadonlySignal<AuthActionState> get actionState =>
      _actionState;

  /// Human-readable error message, set when actionState
  /// is [AuthActionState.error].
  final Signal<String?> _errorMessage = signal(null);
  ReadonlySignal<String?> get errorMessage => _errorMessage;

  // ── Actions ───────────────────────────────────────────────────

  /// Attempt to log in with the given credentials.
  ///
  /// On success the tokens are persisted and the global
  /// authStatus signal transitions to authenticated.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    _actionState.value = AuthActionState.loading;
    _errorMessage.value = null;

    final result = await _repository.login(
      email: email,
      password: password,
    );

    return result.fold(
      (loginResponse) async {
        await markAuthenticated(
          _storage,
          accessToken: loginResponse.accessToken,
          refreshToken: loginResponse.refreshToken,
        );
        _actionState.value = AuthActionState.success;
      },
      (message) {
        _errorMessage.value = message;
        _actionState.value = AuthActionState.error;
      },
    );
  }

  /// Reset state back to idle so the UI can recover from errors.
  void reset() {
    _actionState.value = AuthActionState.idle;
    _errorMessage.value = null;
  }

  /// Dispose all internal signals.
  void dispose() {
    _actionState.dispose();
    _errorMessage.dispose();
  }
}
