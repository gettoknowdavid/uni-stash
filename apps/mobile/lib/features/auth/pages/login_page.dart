import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:forui/forui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';

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
        showFToast(
          context: context,
          title: Text(error),
          variant: .destructive,
          duration: const Duration(seconds: 4),
          alignment: .bottomCenter,
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
    return FScaffold(
      header: const FHeader(title: Text('Login')),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

class _EmailField extends SignalWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();
    return FTextFormField.email(
      label: const Text('SCHOOL EMAIL'),
      enabled: !model.isLoading.value,
      hint: 'you@university.edu',
      autovalidateMode: .onUserInteraction,
      onSaved: model.setEmail,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your email.';
        }
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
          return 'Please enter a valid email.';
        }
        return null;
      },
    );
  }
}

class _PasswordField extends SignalWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();
    return FTextFormField.password(
      label: const Text('PASSWORD'),
      enabled: !model.isLoading.value,
      autovalidateMode: .onUserInteraction,
      onSaved: model.setPassword,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your password.';
        }
        return null;
      },
    );
  }
}

class _LoginButton extends SignalWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<LoginViewModel>();
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: FButton(
        onPress: isBusy ? null : () => _handleLogin(context),
        child: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: FCircularProgress(size: .sm),
              )
            : const Text('Sign in'),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    if (!Form.of(context).validate()) return;
    Form.of(context).save();
    di<LoginViewModel>().submit();
  }
}
