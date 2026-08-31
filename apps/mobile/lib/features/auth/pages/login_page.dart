import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';
import 'package:uni_stash_mobile/theme/us_typography.dart';

class LoginPage extends SignalStatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .fromLTRB(24, 48, 24, 0),
      child: Form(
        key: _formKey,
        child: const Column(
          mainAxisSize: .min,
          children: [
            SizedBox(height: 32),
            _EmailField(),
            SizedBox(height: 24),
            _PasswordField(),
            SizedBox(height: 32),
            _LoginButton(),
          ],
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
    final us = ShadTheme.of(context);

    return ShadInputFormField(
      id: 'email',
      label: Text('SCHOOL EMAIL', style: us.textTheme.labelMd),
      enabled: !model.isLoading.value,
      placeholder: const Text('you@university.edu'),
      autovalidateMode: AutovalidateMode.onUserInteraction,
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

class _PasswordField extends SignalWidget {
  const _PasswordField();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();
    final us = ShadTheme.of(context);

    return ShadInputFormField(
      id: 'password',
      label: Text('PASSWORD', style: us.textTheme.labelMd),
      enabled: !model.isLoading.value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: true,
      onSaved: model.setPassword,
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
    if (!Form.of(context).validate()) return;
    Form.of(context).save();
    di<LoginViewModel>().submit();
  }
}
