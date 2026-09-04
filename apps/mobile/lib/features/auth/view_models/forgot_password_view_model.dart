import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class ForgotPasswordViewModel implements Disposable {
  ForgotPasswordViewModel(this._repository) {
    submit = action0(() async {
      isLoading.value = true;
      error.value = null;

      final request = ForgotPasswordRequest(email: email.value);
      final response = await _repository.forgotPassword(request);

      response.fold(
        (success) => result.value = true,
        (failure) => error.value = failure,
      );

      isLoading.value = false;
    });
  }

  final IAuthRepository _repository;

  final Signal<String> email = Signal('');
  final Signal<bool> isLoading = Signal(false);
  final Signal<String?> error = Signal(null);
  final Signal<bool?> result = Signal(null);

  void setEmail(String? value) => email.value = value ?? '';

  late final void Function() submit;

  void reset() {
    email.value = '';
    error.value = null;
    result.value = null;
  }

  void dispose() {
    email.dispose();
    isLoading.dispose();
    error.dispose();
    result.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
