import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/scope.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// CONFIRM DELETE ACCOUNT dialog: requires the current password, calls
/// `POST /auth/delete-account`, then signs the user out and routes to
/// login. The account is soft-deleted with a 30-day grace period before
/// the background job hard-deletes it.
class DeleteAccountDialog extends SignalHookWidget {
  const DeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final passwordController = useSignal('');
    final isLoading = useSignal(false);
    final error = useSignal<String?>(null);

    Future<void> submit() async {
      final password = passwordController.value.trim();
      if (password.isEmpty) {
        error.value = 'Enter your password to confirm.';
        return;
      }

      isLoading.value = true;
      error.value = null;

      final result = await di<IAuthRepository>().deleteAccount(
        DeleteAccountRequest(password: password),
      );
      isLoading.value = false;

      switch (result) {
        case Success():
          // Mirror logout: drop the session and every scoped dependency.
          di<AuthViewModel>().unauthenticate();
          if (di.hasScope(Scope.root)) {
            await di.popScopesTill(Scope.root, inclusive: false);
          }
          if (context.mounted) {
            context.go(UsRoutes.login);
            ShadToaster.of(context).show(
              const ShadToast(
                title: Text('Account scheduled for deletion'),
                description: Text(
                  'You have 30 days to contact support to cancel. '
                  'After that, your account is permanently deleted.',
                ),
              ),
            );
          }
        case Failure(:final message):
          error.value = message;
      }
    }

    return ShadDialog.alert(
      padding: const .fromLTRB(24, 0, 24, 24),
      title: const Text('DELETE ACCOUNT?'),
      titleStyle: theme.textTheme.h1,
      titleTextAlign: .center,
      description: const Padding(
        padding: .only(bottom: 16),
        child: Text(
          'This schedules your account for permanent deletion in 30 days. '
          'Your listings will stop being visible immediately. This cannot '
          'be undone after the grace period unless you contact support.',
        ),
      ),
      descriptionTextAlign: .left,
      actionsAxis: .horizontal,
      expandActionsWhenTiny: false,
      actions: [
        ShadButton.outline(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          onPressed: isLoading.value ? null : () => context.pop(false),
          child: const Text('CANCEL'),
        ),
        ShadButton.destructive(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          enabled: !isLoading.value,
          onPressed: () => unawaited(submit()),
          child: isLoading.value ? const Spinner() : const Text('DELETE'),
        ),
      ],
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          ShadInput(
            obscureText: true,
            placeholder: const Text('Current password'),
            onChanged: (v) => passwordController.value = v,
            onSubmitted: (_) => unawaited(submit()),
          ),
          if (error.value != null) ...[
            const SizedBox(height: 8),
            Text(
              error.value!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
