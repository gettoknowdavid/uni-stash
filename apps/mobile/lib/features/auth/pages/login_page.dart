import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/auth_page_shell.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({LoginViewModel? viewModel, super.key})
    : _viewModel = viewModel;

  final LoginViewModel? _viewModel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<ShadFormState>();

  late final LoginViewModel _model;

  /// Whether this widget owns the ViewModel (and should dispose it).
  bool get _ownsModel => widget._viewModel == null;

  @override
  void initState() {
    super.initState();
    _model = widget._viewModel ?? LoginViewModel(di<IAuthRepository>());
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
              accessToken: response.accessToken,
              refreshToken: response.refreshToken,
              expiresIn: response.expiresIn,
            ),
          );
          _model.reset();
        }

        final error = _model.error.value;
        if (error != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ShadToaster.of(context).show(
              ShadToast.destructive(
                title: const Text('Authentication Error'),
                description: Text(error),
              ),
            );
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SingleChildScrollView(
          child: AuthPageShell(
            footer: Row(
              mainAxisAlignment: .center,
              children: [
                Text("Dont't have an account?", style: theme.textTheme.muted),
                const SizedBox(width: 6),
                ShadButton.link(
                  padding: .zero,
                  foregroundColor: theme.colorScheme.textSecondary,
                  textStyle: theme.textTheme.muted,
                  child: const Text('SIGN UP'),
                  onPressed: () => context.push(UsRoutes.signup),
                ),
              ],
            ),
            child: ShadForm(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _EmailField(model: _model),
                  const SizedBox(height: 24),
                  _PasswordField(model: _model),
                  const SizedBox(height: 32),
                  _LoginButton(
                    model: _model,
                    formKey: _formKey,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends SignalWidget {
  const _EmailField({required this.model});
  final LoginViewModel model;

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      id: 'email',
      label: const Text('SCHOOL EMAIL'),
      enabled: !model.isLoading.value,
      placeholder: const Text('you@university.edu'),
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
  final LoginViewModel model;

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
        return null;
      },
    );
  }
}

class _LoginButton extends SignalWidget {
  const _LoginButton({required this.model, required this.formKey});
  final LoginViewModel model;
  final GlobalKey<ShadFormState> formKey;

  @override
  Widget build(BuildContext context) {
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : () => _handleLogin(context),
        child: isBusy ? const ShadSpinner() : const Text('LOG IN'),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    if (!ShadForm.of(context).saveAndValidate()) return;
    model.submit();
  }
}
