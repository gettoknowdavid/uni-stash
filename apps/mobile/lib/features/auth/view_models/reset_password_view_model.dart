import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

/// Drives the reset-password (OTP + new password) page.
///
/// [email] is the address the recovery code was sent to; it's used to resend
/// the code (via the forgot-password endpoint) and to confirm delivery.
class ResetPasswordViewModel implements Disposable {
  ResetPasswordViewModel(this._repository, {required this.email}) {
    submit = action0(() async {
      if (isLoading.value) return;
      isLoading.value = true;
      error.value = null;

      final request = ResetPasswordRequest(
        code: code.value,
        newPassword: newPassword.value,
      );
      final response = await _repository.resetPassword(request);

      switch (response) {
        case Success():
          result.value = true;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });

    resend = action0(() async {
      if (isResending.value) return;
      if (email.isEmpty) {
        error.value = 'We need an email address to resend the code. '
            'Please start again.';
        return;
      }
      isResending.value = true;
      error.value = null;

      final request = ForgotPasswordRequest(email: email);
      final response = await _repository.forgotPassword(request);

      switch (response) {
        case Success():
          resendMessage.value = 'A new reset code was sent to $email.';
        case Failure(:final message):
          error.value = message;
      }

      isResending.value = false;
    });
  }

  final IAuthRepository _repository;

  /// The account email the recovery code was sent to.
  final String email;

  final Signal<String> code = Signal('');
  final Signal<String> newPassword = Signal('');
  final Signal<String> confirmPassword = Signal('');
  final Signal<bool> isLoading = Signal(false);
  final Signal<bool> isResending = Signal(false);
  final Signal<String?> error = Signal(null);

  /// Set after a successful resend, so the page can confirm to the user.
  final Signal<String?> resendMessage = Signal(null);

  /// Becomes `true` once the password has been changed successfully.
  final Signal<bool?> result = Signal(null);

  void setCode(String? value) {
    code.value = (value ?? '').replaceAll(RegExp('[^0-9]'), '');
  }

  void setNewPassword(String? value) => newPassword.value = value ?? '';

  void setConfirmPassword(String? value) =>
      confirmPassword.value = value ?? '';

  late final void Function() submit;
  late final void Function() resend;

  void reset() {
    code.value = '';
    newPassword.value = '';
    confirmPassword.value = '';
    isLoading.value = false;
    isResending.value = false;
    error.value = null;
    resendMessage.value = null;
    result.value = null;
  }

  void dispose() {
    code.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    isLoading.dispose();
    isResending.dispose();
    error.dispose();
    resendMessage.dispose();
    result.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
