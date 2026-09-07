import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class LoginViewModel implements Disposable {
  LoginViewModel(this._repository) {
    submit = action0(() async {
      isLoading.value = true;
      error.value = null;

      final req = LoginRequest(email: email.value, password: password.value);
      final response = await _repository.login(req);

      switch (response) {
        case Success(:final value):
          result.value = value;
        case Failure(:final message, :final code):
          error.value = message;
          // Backend 403 email_not_verified: the credentials are right but
          // the account still needs its OTP flow finished, so the page can
          // route the user to the verification screen.
          if (code == AuthErrorCode.emailNotVerified) {
            needsVerification.value = true;
          }
      }

      isLoading.value = false;
    });
  }

  final IAuthRepository _repository;

  final Signal<String> email = Signal('');
  final Signal<String> password = Signal('');
  final Signal<bool> isLoading = Signal(false);
  final Signal<String?> error = Signal(null);
  final Signal<LoginResponse?> result = Signal(null);

  /// True when the last login attempt failed because the account's email is
  /// not yet verified, signalling the page to take the user to `/verify`.
  final Signal<bool> needsVerification = Signal(false);

  void setEmail(String? value) => email.value = value ?? '';

  void setPassword(String? value) => password.value = value ?? '';

  late final void Function() submit;

  void reset() {
    email.value = '';
    password.value = '';
    isLoading.value = false;
    error.value = null;
    result.value = null;
    needsVerification.value = false;
  }

  void dispose() {
    email.dispose();
    password.dispose();
    isLoading.dispose();
    error.dispose();
    result.dispose();
    needsVerification.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
