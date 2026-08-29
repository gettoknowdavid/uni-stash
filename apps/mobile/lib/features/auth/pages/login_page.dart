import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/us_routes.dart';
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

  late final LoginViewModel _model;

  late final Logger _logger;
  EffectCleanup? _onLogin;

  @override
  void initState() {
    super.initState();
    _model = LoginViewModel(di<IAuthRepository>());

    _logger = di<Logger>();

    // Watch for successful login — the global authStatus signal change
    // will trigger the router redirect automatically.
    _onLogin = effect(() {
      final response = _model.result.value;
      if (response == null) return;
      final credentials = UserCredentials(
        user: response.user,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresIn: response.expiresIn,
      );
      di<AuthViewModel>().authenticate(credentials);
      _model.reset();
    });
  }

  @override
  void dispose() {
    _onLogin?.call();
    _model.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    _model.submit();
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: const FHeader(title: Text('Login')),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),

              SignalBuilder(
                builder: (context) {
                  return FTextFormField.email(
                    enabled: !_model.isLoading.value,
                    autofocus: true,
                    autovalidateMode: .onUserInteraction,
                    onSaved: _model.setEmail,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email.';
                      }
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(value.trim())) {
                        return 'Please enter a valid email.';
                      }
                      return null;
                    },
                  );
                },
              ),

              const SizedBox(height: 16),

              SignalBuilder(
                builder: (context) {
                  return FTextFormField.password(
                    enabled: !_model.isLoading.value,
                    textInputAction: .done,
                    autovalidateMode: .onUserInteraction,
                    onSaved: _model.setPassword,
                    onSubmit: (_) => _handleLogin(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password.';
                      }
                      return null;
                    },
                  );
                },
              ),

              const SizedBox(height: 24),

              SignalBuilder(
                builder: (ctx) {
                  final error = _model.error.value;
                  if (error == null) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ctx.theme.colors.destructive.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ctx.theme.colors.destructive),
                    ),
                    child: Text(
                      error,
                      style: ctx.theme.typography.body.sm.copyWith(
                        color: ctx.theme.colors.destructive,
                      ),
                    ),
                  );
                },
              ),

              SignalBuilder(
                builder: (context) {
                  final hasError = _model.error.value != null;
                  if (!hasError) return const SizedBox.shrink();
                  return const SizedBox(height: 16);
                },
              ),

              SignalBuilder(
                builder: (context) {
                  final isBusy = _model.isLoading.value;
                  return SizedBox(
                    width: double.infinity,
                    child: FButton(
                      onPress: isBusy ? null : _handleLogin,
                      child: isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: FCircularProgress(size: .sm),
                            )
                          : const Text('Sign in'),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── Forgot password link ──────────────────────────────
              TextButton(
                onPressed: () => context.push(UsRoutes.forgotPw),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
