import 'dart:async';

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

class LoginPage extends SignalStatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<ShadFormState>();

  EffectCleanup? _onLogin;
  EffectCleanup? _onError;

  @override
  void initState() {
    super.initState();
    di.pushNewScope(
      scopeName: 'login',
      init: (getIt) => getIt.registerLazySingleton(
        () => LoginViewModel(getIt<IAuthRepository>()),
      ),
    );

    _onLogin = effect(() {
      final response = di<LoginViewModel>().result.value;
      if (response == null) return;
      final credentials = UserCredentials(
        user: response.user,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresIn: response.expiresIn,
      );
      di<AuthViewModel>().authenticate(credentials);
      di<LoginViewModel>().reset();
    });

    _onError = effect(() {
      final error = di<LoginViewModel>().error.value;
      if (error == null) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Authentication Error'),
            description: Text(error),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _onLogin?.call();
    _onError?.call();
    unawaited(di.popScope());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        child: AuthPageShell(
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
                textStyle: theme.textTheme.muted.copyWith(
                  color: theme.colorScheme.secondary,
                ),
                child: const Text('Sign Up'),
                onPressed: () => context.push(UsRoutes.signup),
              ),
            ],
          ),
          child: ShadForm(
            key: _formKey,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EmailField(),
                SizedBox(height: 24),
                _PasswordField(),
                SizedBox(height: 32),
                _LoginButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends SignalWidget {
  const _EmailField();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();

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

class _PasswordField extends StatefulWidget {
  const _PasswordField();

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();

    return ShadInputFormField(
      id: 'password',
      label: const Text('PASSWORD'),
      enabled: !model.isLoading.value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: _obscure,
      onSaved: model.setPassword,
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
  const _LoginButton();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();
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
    di<LoginViewModel>().submit();
  }
}
