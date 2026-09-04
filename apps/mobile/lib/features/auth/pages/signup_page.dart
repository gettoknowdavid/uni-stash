import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/_view_models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({SignUpViewModel? viewModel, super.key})
    : _viewModel = viewModel;

  final SignUpViewModel? _viewModel;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<ShadFormState>();

  late final SignUpViewModel _model;

  /// Whether this widget owns the ViewModel (and should dispose it).
  bool get _ownsModel => widget._viewModel == null;

  @override
  void initState() {
    super.initState();
    _model = widget._viewModel ?? SignUpViewModel(di<IAuthRepository>());
  }

  @override
  void dispose() {
    if (_ownsModel) _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SignalEffect(
      effect: (context) {
        final response = _model.result.value;
        if (response != null) {
          di<AuthViewModel>().authenticate(
            UserCredentials(
              user: response.user,
              accessToken: response.accessToken ?? '',
              refreshToken: response.refreshToken ?? '',
              expiresIn: response.expiresIn ?? 0,
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
        }
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              AuthPageShell(
                title: const Text('UNI·STASH'),
                subtitle: const Text('Campus Bulletin Board'),
                body: ShadForm(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      _DisplayNameField(model: _model),
                      const SizedBox(height: 24),
                      _EmailField(model: _model),
                      const SizedBox(height: 24),
                      _PasswordField(model: _model),
                      const SizedBox(height: 40),
                      _SignUpButton(
                        model: _model,
                        formKey: _formKey,
                      ),
                    ],
                  ),
                ),
                footer: Row(
                  mainAxisAlignment: .center,
                  children: [
                    Text(
                      'Already have an account?',
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(width: 6),
                    ShadButton.link(
                      padding: .zero,
                      foregroundColor: theme.colorScheme.textSecondary,
                      textStyle: theme.textTheme.muted,
                      child: const Text('LOG IN'),
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const GreenNoticeCard(
                title: 'CAMPUS VERIFICATION',
                description:
                    'We verify all new members against active recognized '
                    'school domain lists (.edu, .edu.ng, etc.) to ensure '
                    'a safe, closed community.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayNameField extends SignalWidget {
  const _DisplayNameField({required this.model});
  final SignUpViewModel model;

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      id: 'displayName',
      label: const Text('DISPLAY NAME'),
      enabled: !model.isLoading.value,
      placeholder: const Text('John Doe'),
      autovalidateMode: .onUserInteraction,
      onSaved: model.setDisplayName,
      validator: (value) {
        if (value.trim().isEmpty) return 'Please enter your name';
        return null;
      },
    );
  }
}

class _EmailField extends SignalWidget {
  const _EmailField({required this.model});
  final SignUpViewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadInputFormField(
      id: 'email',
      label: const Text('SCHOOL EMAIL'),
      enabled: !model.isLoading.value,
      placeholder: const Text('you@university.edu'),
      trailing: Icon(
        LucideIcons.atSign,
        size: 16,
        color: theme.colorScheme.mutedForeground,
      ),
      autovalidateMode: .onUserInteraction,
      onSaved: model.setEmail,
      validator: (value) {
        if (value.trim().isEmpty) return 'Please enter your email.';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
          return 'Please enter a valid email.';
        }
        return null;
      },
    );
  }
}

class _PasswordField extends SignalStatefulWidget {
  const _PasswordField({required this.model});
  final SignUpViewModel model;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      id: 'password',
      label: const Text('PASSWORD'),
      placeholder: const Text('•••••••••••'),
      enabled: !widget.model.isLoading.value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: _obscure,
      onSaved: widget.model.setPassword,
      trailing: SizedBox.square(
        dimension: 24,
        child: OverflowBox(
          maxWidth: 28,
          maxHeight: 28,
          child: ShadIconButton.ghost(
            iconSize: 20,
            padding: const .all(2),
            icon: Icon(_obscure ? LucideIcons.eyeOff : LucideIcons.eye),
            onPressed: () {
              setState(() => _obscure = !_obscure);
            },
          ),
        ),
      ),
      validator: (value) {
        if (value.isEmpty) return 'Please enter your password.';
        if (value.length < 8) {
          return 'Password must be at least 8 characters.';
        }
        return null;
      },
    );
  }
}

class _SignUpButton extends SignalWidget {
  const _SignUpButton({required this.model, required this.formKey});
  final SignUpViewModel model;
  final GlobalKey<ShadFormState> formKey;

  @override
  Widget build(BuildContext context) {
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : () => _handleSignUp(context),
        child: isBusy ? const ShadSpinner() : const Text('SIGN UP'),
      ),
    );
  }

  Future<void> _handleSignUp(BuildContext context) async {
    if (!ShadForm.of(context).saveAndValidate()) return;
    model.submit();
  }
}
