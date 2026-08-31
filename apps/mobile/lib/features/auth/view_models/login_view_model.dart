import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class LoginViewModel implements Disposable {
  LoginViewModel(this._repository) {
    submit = action0(() async {
      isLoading.value = true;
      error.value = null;

      final req = LoginRequest(email: email.value, password: password.value);
      final response = await _repository.login(req);

      response.fold(
        (data) => result.value = data,
        (message) => error.value = message,
      );

      isLoading.value = false;
    });
  }

  final IAuthRepository _repository;

  final Signal<String> email = Signal('');
  final Signal<String> password = Signal('');
  final Signal<bool> isLoading = Signal(false);
  final Signal<String?> error = Signal(null);
  final Signal<LoginResponse?> result = Signal(null);

  void setEmail(String? value) => email.value = value ?? '';

  void setPassword(String? value) => password.value = value ?? '';

  late final void Function() submit;

  void reset() {
    email.value = '';
    password.value = '';
    isLoading.value = false;
    error.value = null;
    result.value = null;
  }

  void dispose() {
    email.dispose();
    password.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
