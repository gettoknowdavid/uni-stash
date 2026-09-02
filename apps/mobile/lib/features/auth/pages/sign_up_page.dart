import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/sign_up_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';

class SignUpPage extends SignalStatefulWidget {
  const new({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<ShadFormState>();

  EffectCleanup? _onSignUp;
  EffectCleanup? _onError;

  @override
  void initState() {
    super.initState();
    di.pushNewScope(
      scopeName: 'signup',
      init: (getIt) => getIt.registerLazySingleton(
        () => SignUpViewModel(getIt<IAuthRepository>()),
      ),
    );

    _onSignUp = effect(() {
      final response = di<SignUpViewModel>().result.value;
      if (response == null) return;
      final credentials = UserCredentials(
        user: response.user,
        accessToken: response.accessToken ?? '',
        refreshToken: response.refreshToken ?? '',
        expiresIn: response.expiresIn ?? 0,
      );
      di<AuthViewModel>().authenticate(credentials);
      di<SignUpViewModel>().reset();
    });

    _onError = effect(() {
      final error = di<SignUpViewModel>().error.value;
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
    _onSignUp?.call();
    _onError?.call();
    unawaited(di.popScope());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const .fromLTRB(24, 0, 24, 0),
        child: ShadForm(
          key: _formKey,
          child: const Column(
            mainAxisSize: .min,
            children: [
              SizedBox(height: 16),
              _DisplayNameField(),
              SizedBox(height: 24),
              _EmailField(),
              SizedBox(height: 24),
              _PasswordField(),
              SizedBox(height: 32),
              _SignUpButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayNameField extends SignalWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<SignUpViewModel>();

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
  const _EmailField();

  @override
  Widget build(BuildContext context) {
    final model = di<SignUpViewModel>();

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
  const new();

  @override
  State<_PasswordField> createState() => __PasswordFieldState();
}

class __PasswordFieldState extends State<_PasswordField> {
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final model = di<SignUpViewModel>();

    return ShadInputFormField(
      id: 'password',
      label: const Text('PASSWORD'),
      enabled: !model.isLoading.value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      obscureText: obscure,
      onSaved: model.setPassword,
      trailing: SizedBox.square(
        dimension: 24,
        child: OverflowBox(
          maxWidth: 28,
          maxHeight: 28,
          child: ShadIconButton.ghost(
            iconSize: 20,
            padding: const .all(2),
            icon: Icon(obscure ? LucideIcons.eyeOff : LucideIcons.eye),
            onPressed: () {
              setState(() => obscure = !obscure);
            },
          ),
        ),
      ),
      validator: (value) {
        if (value.isEmpty) return 'Please enter your password.';
        if (value.length < 8) return 'Password must be at least 8 characters.';
        return null;
      },
    );
  }
}

class _SignUpButton extends SignalWidget {
  const _SignUpButton();

  @override
  Widget build(BuildContext context) {
    final model = di<SignUpViewModel>();
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
    di<SignUpViewModel>().submit();
  }
}
