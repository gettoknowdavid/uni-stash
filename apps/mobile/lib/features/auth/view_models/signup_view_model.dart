import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class SignUpViewModel implements Disposable {
  SignUpViewModel(this._repository) {
    submit = action0(() async {
      isLoading.value = true;
      error.value = null;

      final req = SignUpRequest(
        email: email.value,
        password: password.value,
        displayName: displayName.value,
      );
      final response = await _repository.signUp(req);

      response.fold(
        (value) => result.value = value,
        (message) => error.value = message,
      );

      isLoading.value = false;
    });
  }

  final IAuthRepository _repository;

  final Signal<String> displayName = Signal<String>('');
  final Signal<String> email = Signal<String>('');
  final Signal<String> password = Signal<String>('');
  final Signal<String> confirmPassword = Signal<String>('');
  final Signal<bool> isLoading = Signal<bool>(false);
  final Signal<String?> error = Signal<String?>(null);
  final Signal<SignUpResponse?> result = Signal(null);

  void setDisplayName(String? value) => displayName.value = value ?? '';

  void setEmail(String? value) => email.value = value ?? '';

  void setPassword(String? value) => password.value = value ?? '';

  void setConfirmPassword(String? value) => confirmPassword.value = value ?? '';

  late final void Function() submit;

  void reset() {
    displayName.value = '';
    email.value = '';
    password.value = '';
    confirmPassword.value = '';
    isLoading.value = false;
    error.value = null;
    result.value = null;
  }

  void dispose() {
    displayName.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    isLoading.dispose();
    error.dispose();
    result.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
