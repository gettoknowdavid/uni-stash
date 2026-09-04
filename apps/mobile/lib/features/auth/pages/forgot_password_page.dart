import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/view_models/forgot_password_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class ForgotPasswordPage extends SignalStatefulWidget {
  const new({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<ShadFormState>();

  late final ForgotPasswordViewModel _model;

  @override
  void initState() {
    super.initState();
    // Each visit gets its own page-scoped ViewModel: the scope gives sub-
    // widgets a single shared instance and makes GetIt dispose it (via the
    // model's Disposable contract) when the scope is popped in dispose().
    di.pushNewScope(
      scopeName: 'forgotPasswordPage',
      init: (getIt) {
        getIt.registerLazySingleton<ForgotPasswordViewModel>(
          () => ForgotPasswordViewModel(di<IAuthRepository>()),
        );
      },
    );
    _model = di<ForgotPasswordViewModel>();
  }

  @override
  void dispose() {
    unawaited(di.popScope());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const .only(top: 16),
        child: AuthPageShell(
          title: Align(
            alignment: .centerLeft,
            child: Text('FORGOT PASSWORD', style: theme.textTheme.h1),
          ),
          description: const Text(
            'Enter your registered campus email address and '
            "we'll dispatch a 6-digit recovery code.",
          ),
          body: SignalEffect(
            effect: (context) {
              if (_model.result.value ?? false) {
                unawaited(context.push(UsRoutes.resetPw));
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
            child: ShadForm(
              key: _formKey,
              child: const Column(
                children: [
                  _EmailField(),
                  SizedBox(height: 32),
                  _SubmitButton(),
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
  const _EmailField();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<ForgotPasswordViewModel>();
    return ShadInputFormField(
      id: 'email',
      label: const Text('SCHOOL EMAIL'),
      enabled: !model.isLoading.value,
      placeholder: const Text('you@university.edu'),
      autovalidateMode: .onUserInteraction,
      trailing: Icon(
        LucideIcons.atSign,
        size: 16,
        color: theme.colorScheme.mutedForeground,
      ),
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

class _SubmitButton extends SignalWidget {
  const _SubmitButton();

  @override
  Widget build(BuildContext context) {
    final model = di<ForgotPasswordViewModel>();
    final isBusy = model.isLoading.value;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : () => _handleSignUp(context),
        child: isBusy ? const ShadSpinner() : const Text('SUBMIT'),
      ),
    );
  }

  Future<void> _handleSignUp(BuildContext context) async {
    if (!ShadForm.of(context).saveAndValidate()) return;
    di<ForgotPasswordViewModel>().submit();
  }
}
