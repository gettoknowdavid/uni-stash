import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/auth/widgets/us_otp_input.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class ResetPasswordPage extends SignalStatefulWidget {
  const ResetPasswordPage({this.email, super.key});

  /// The email the recovery code was sent to (route query), used for display
  /// and for resending the code.
  final String? email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<ShadFormState>();

  late final ResetPasswordViewModel _model;

  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;

  String? _codeError;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'resetPasswordPage',
      init: (getIt) {
        getIt.registerLazySingleton<ResetPasswordViewModel>(
          () => ResetPasswordViewModel(
            di<IAuthRepository>(),
            email: widget.email ?? '',
          ),
        );
      },
    );
    _model = di<ResetPasswordViewModel>();
  }

  @override
  void dispose() {
    // popScope() is async but dispose() is sync, so the pop is fired,
    // not awaited — see [popPageScope].
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalEffect(
      effect: (context) {
        if (_model.result.value ?? false) {
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('Password Reset'),
              description: Text(
                'Your password has been updated. Sign in with your new '
                'password.',
              ),
            ),
          );
          _model.reset();
          context.go(UsRoutes.login);
        }

        final resendMessage = _model.resendMessage.value;
        if (resendMessage != null) {
          ShadToaster.of(context).show(
            ShadToast(
              title: const Text('Code Sent'),
              description: Text(resendMessage),
            ),
          );
          _model.reset();
        }

        final error = _model.error.value;
        if (error != null) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Authentication Error'),
              description: Text(error),
            ),
          );
          _model.reset();
        }
      },
      child: UsPage(
        header: const UsPageHeader(),
        body: SingleChildScrollView(
          padding: const .only(top: 16),
          child: AuthPageShell(
            title: Align(
              alignment: .centerLeft,
              child: Text('RESET PASSWORD', style: theme.textTheme.h1),
            ),
            description: widget.email == null || widget.email!.isEmpty
                ? const Text(
                    'Enter the 6-digit code from your email and choose a '
                    'new password.',
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "We've sent a 6-digit code to ${widget.email}.",
                        ),
                        const TextSpan(
                          text: ' Enter it below and choose a new password.',
                        ),
                      ],
                      style: theme.textTheme.muted.copyWith(
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
            body: ShadForm(
              key: _formKey,
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Text(
                    'RECOVERY CODE',
                    style: theme.textTheme.muted.copyWith(
                      fontSize: 12,
                      fontWeight: .bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(child: UsOtpInput(onChanged: _handleCodeChanged)),
                  if (_codeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _codeError!,
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.destructive,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _NewPasswordField(),
                  const SizedBox(height: 24),
                  const _ConfirmPasswordField(),
                  const SizedBox(height: 32),
                  _SubmitButton(onSubmit: _handleSubmit),
                  const SizedBox(height: 8),
                  const _ResendButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleCodeChanged(String value) {
    if (_codeError != null) setState(() => _codeError = null);
    _model.setCode(value);
  }

  Future<void> _handleSubmit() async {
    if (_model.code.value.length != 6) {
      setState(() => _codeError = 'Please enter the complete 6-digit code.');
    }
    if (!_formKey.currentState!.saveAndValidate()) return;
    if (_codeError != null) return;
    _model.submit();
  }
}

class _NewPasswordField extends SignalWidget {
  const _NewPasswordField();

  @override
  Widget build(BuildContext context) {
    final model = di<ResetPasswordViewModel>();
    return ShadInputFormField(
      id: 'newPassword',
      label: const Text('NEW PASSWORD'),
      enabled: !model.isLoading.value,
      placeholder: const Text('•••••••••••'),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: true,
      onSaved: model.setNewPassword,
      validator: (value) {
        if (value.isEmpty) return 'Please enter a new password.';
        if (value.length < 10) {
          return 'Password must be at least 10 characters.';
        }
        return null;
      },
    );
  }
}

class _ConfirmPasswordField extends SignalWidget {
  const _ConfirmPasswordField();

  @override
  Widget build(BuildContext context) {
    final model = di<ResetPasswordViewModel>();
    return ShadInputFormField(
      id: 'confirmPassword',
      label: const Text('CONFIRM PASSWORD'),
      enabled: !model.isLoading.value,
      placeholder: const Text('•••••••••••'),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: true,
      onSaved: model.setConfirmPassword,
      validator: (value) {
        if (value.isEmpty) return 'Please confirm your password.';
        if (value != model.newPassword.value) {
          return 'Passwords do not match.';
        }
        return null;
      },
    );
  }
}

class _SubmitButton extends SignalWidget {
  const _SubmitButton({required this.onSubmit});

  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final model = di<ResetPasswordViewModel>();
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : onSubmit,
        child: isBusy ? const Spinner() : const Text('SET NEW PASSWORD'),
      ),
    );
  }
}

class _ResendButton extends SignalWidget {
  const _ResendButton();

  @override
  Widget build(BuildContext context) {
    final model = di<ResetPasswordViewModel>();
    final isBusy = model.isResending.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton.ghost(
        onPressed: isBusy ? null : model.resend,
        child: isBusy ? const Spinner() : const Text('Resend Code'),
      ),
    );
  }
}
