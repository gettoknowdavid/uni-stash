import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/us_routes.dart';
import 'package:uni_stash_mobile/features/auth/notifiers/auth_notifier.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  late final AuthNotifier _auth;
  late final Logger _logger;
  EffectCleanup? _authEffect;

  String? _email;
  String? _password;

  @override
  void initState() {
    super.initState();
    _auth = di<AuthNotifier>();
    _logger = di<Logger>();

    // Watch for successful login — the global authStatus signal change
    // will trigger the router redirect automatically.
    _authEffect = effect(() {
      final state = _auth.actionState.value;
      if (state == AuthActionState.success) {
        _logger.d('[LoginPage] Login succeeded');
        untracked(() => _auth.reset());
      }
    });
  }

  @override
  void dispose() {
    _authEffect?.call();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final email = _email ?? '';
    final password = _password ?? '';

    await _auth.login(email: email, password: password);
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

              // ── Email ─────────────────────────────────────────────
              SignalBuilder(
                builder: (context) {
                  final isBusy =
                      _auth.actionState.value == AuthActionState.loading;
                  return FTextFormField.email(
                    enabled: !isBusy,
                    autofocus: true,
                    autovalidateMode: .onUserInteraction,
                    onSaved: (value) => _email = value,
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

              // ── Password ──────────────────────────────────────────
              SignalBuilder(
                builder: (context) {
                  final isBusy =
                      _auth.actionState.value == AuthActionState.loading;
                  return FTextFormField.password(
                    enabled: !isBusy,
                    textInputAction: .done,
                    autovalidateMode: .onUserInteraction,
                    onSaved: (value) => _password = value,
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

              // ── Error banner ──────────────────────────────────────
              SignalBuilder(
                builder: (context) {
                  final error = _auth.errorMessage.value;
                  if (error == null) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.theme.colors.destructive.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: context.theme.colors.destructive,
                      ),
                    ),
                    child: Text(
                      error,
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.destructive,
                      ),
                    ),
                  );
                },
              ),

              SignalBuilder(
                builder: (context) {
                  final hasError = _auth.errorMessage.value != null;
                  if (!hasError) return const SizedBox.shrink();
                  return const SizedBox(height: 16);
                },
              ),

              // ── Sign-in button ────────────────────────────────────
              SignalBuilder(
                builder: (context) {
                  final isBusy =
                      _auth.actionState.value == AuthActionState.loading;
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
