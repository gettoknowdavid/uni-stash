import 'package:get_it/get_it.dart';
import 'package:logger/web.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/auth/widgets/us_otp_input.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class VerifyPage extends SignalStatefulWidget {
  const VerifyPage({this.email, this.code, super.key});

  /// The pending account email, taken from the route query (`/verify?email=`)
  /// when the user arrives without an active session.
  final String? email;

  /// Optional pre-filled OTP code, taken from the route query
  /// (`/verify?code=`) so tests and deep-links can seed the input.
  final String? code;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  late final VerifyOtpViewModel _model;

  /// Which email the code was sent to: the signed-in user's address wins,
  /// falling back to the one carried on the route (login-rejection path).
  late final String _email;

  String? _code;

  String? _codeError;

  @override
  void initState() {
    super.initState();
    final signedInEmail = di<AuthViewModel>().user.value?.email ?? '';
    _email = signedInEmail.isNotEmpty ? signedInEmail : (widget.email ?? '');
    _code = widget.code;

    di.pushNewScope(
      scopeName: 'verifyPage',
      init: (getIt) {
        getIt.registerLazySingleton<VerifyOtpViewModel>(
          () => VerifyOtpViewModel(
            di<IAuthRepository>(),
            email: _email,
          ),
        );
      },
    );
    _model = di<VerifyOtpViewModel>();
    // If the code was seeded via the route query (used by tests and
    // deep-links), push it straight into the ViewModel so the VERIFY button
    // can submit.
    if (_code != null) {
      _model.setCode(_code);
    }
  }

  @override
  void didUpdateWidget(VerifyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating to /verify?code=... while already on /verify reuses this
    // State (same route path), so re-seed whenever a new code arrives.
    // Guard against a disposed ViewModel: during test router redirects the
    // GetIt scope may already have been popped before this callback runs.
    if (!GetIt.I.isRegistered<VerifyOtpViewModel>()) return;
    final newCode = widget.code;
    if (newCode != null && newCode != _code) {
      _code = newCode;
      _model.setCode(newCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalEffect(
      effect: (context) {
        final response = _model.result.value;
        if (response != null && response.verified) {
          final user = response.user;
          final accessToken = response.accessToken;
          final refreshToken = response.refreshToken;
          if (user != null && accessToken != null && refreshToken != null) {
            di<AuthViewModel>().authenticate(
              UserCredentials(
                user: user,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: response.expiresIn ?? 0,
              ),
            );
          }
          _model.reset();
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
              title: const Text('Verification Error'),
              description: Text(error),
            ),
          );
          _model.reset();
        }
      },
      child: UsPage(
        header: const UsPageHeader(),
        gutters: .zero,
        body: SingleChildScrollView(
          padding: const .only(top: 16),
          child: AuthPageShell(
            title: Align(
              alignment: .centerLeft,
              child: Text('VERIFY EMAIL', style: theme.textTheme.h1),
            ),
            description: _email.isEmpty
                ? const Text(
                    'Enter the 6-digit code sent to your email to activate '
                    'your account.',
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: "We've sent a 6-digit code to ",
                        ),
                        TextSpan(
                          text: _email,
                          style: theme.textTheme.muted.copyWith(
                            color: theme.colorScheme.foreground,
                            fontWeight: .bold,
                          ),
                        ),
                        const TextSpan(
                          text: '. Enter it below to activate your account.',
                        ),
                      ],
                      style: theme.textTheme.muted.copyWith(
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
            body: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  'VERIFICATION CODE',
                  style: theme.textTheme.muted.copyWith(
                    fontSize: 12,
                    fontWeight: .bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: UsOtpInput(
                    onChanged: _handleCodeChanged,
                    initialValue: _code,
                  ),
                ),
                if (_codeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _codeError!,
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _VerifyButton(
                  model: _model,
                  onVerify: _handleVerify,
                ),
                const SizedBox(height: 8),
                _ResendButton(model: _model),
              ],
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

  Future<void> _handleVerify(BuildContext context) async {
    di<Logger>().w(_model.code.value);
    di<Logger>().w(_model.code.value.length);
    if (_model.code.value.length != 6) {
      setState(() => _codeError = 'Please enter the complete 6-digit code.');
      return;
    }
    _model.submit();
  }
}

class _VerifyButton extends SignalWidget {
  const _VerifyButton({required this.model, required this.onVerify});

  final VerifyOtpViewModel model;
  final void Function(BuildContext context) onVerify;

  @override
  Widget build(BuildContext context) {
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : () => onVerify(context),
        child: isBusy ? const ShadSpinner() : const Text('VERIFY'),
      ),
    );
  }
}

class _ResendButton extends SignalWidget {
  const _ResendButton({required this.model});

  final VerifyOtpViewModel model;

  @override
  Widget build(BuildContext context) {
    final isBusy = model.isResending.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton.ghost(
        onPressed: isBusy ? null : model.resend,
        child: isBusy ? const ShadSpinner() : const Text('Resend Code'),
      ),
    );
  }
}
