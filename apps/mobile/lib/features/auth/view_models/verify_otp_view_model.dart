import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

/// Drives the email-verification (OTP) page.
///
/// Mirrors the other page-scoped auth view models: plain signals for form
/// state, an action for the async submit, and signals for error/result that
/// the page reacts to. [email] is the address the code was sent to — used
/// when (re)sending the code.
class VerifyOtpViewModel implements Disposable {
  VerifyOtpViewModel(this._repository, {required this.email}) {
    submit = action0(() async {
      if (isLoading.value) return;
      isLoading.value = true;
      error.value = null;
      resendMessage.value = null;

      final request = VerifyOtpRequest(
        code: code.value,
        otpType: 'email_verify',
      );
      final response = await _repository.verifyOtp(request);

      switch (response) {
        case Success(:final value):
          result.value = value;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });

    resend = action0(() async {
      if (isResending.value) return;
      if (email.isEmpty) {
        error.value = 'We need an email address to resend the code. '
            'Please sign in again.';
        return;
      }
      isResending.value = true;
      error.value = null;
      resendMessage.value = null;

      final request = ResendVerificationRequest(email: email);
      final response = await _repository.resendVerification(request);

      switch (response) {
        case Success():
          resendMessage.value = 'A new verification code was sent to $email.';
        case Failure(:final message):
          error.value = message;
      }

      isResending.value = false;
    });
  }

  final IAuthRepository _repository;

  /// The account email the OTP was sent to (used to resend the code).
  final String email;

  final Signal<String> code = Signal('');
  final Signal<bool> isLoading = Signal(false);
  final Signal<bool> isResending = Signal(false);
  final Signal<String?> error = Signal(null);

  /// Set after a successful resend, so the page can confirm to the user.
  final Signal<String?> resendMessage = Signal(null);
  final Signal<VerifyOtpResponse?> result = Signal(null);

  void setCode(String? value) {
    code.value = (value ?? '').replaceAll(RegExp('[^0-9]'), '');
  }

  late final void Function() submit;
  late final void Function() resend;

  void reset() {
    code.value = '';
    isLoading.value = false;
    isResending.value = false;
    error.value = null;
    resendMessage.value = null;
    result.value = null;
  }

  void dispose() {
    code.dispose();
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
