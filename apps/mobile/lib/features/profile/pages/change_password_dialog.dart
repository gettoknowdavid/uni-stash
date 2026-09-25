import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// CHANGE PASSWORD dialog: re-authenticates with the current password,
/// then calls `POST /auth/change-password`. On success the backend
/// revokes every other session; the current one stays signed in.
class ChangePasswordDialog extends SignalHookWidget {
  const ChangePasswordDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final currentController = useSignal('');
    final newController = useSignal('');
    final confirmController = useSignal('');
    final isLoading = useSignal(false);
    final error = useSignal<String?>(null);

    Future<void> submit() async {
      final current = currentController.value;
      final newPw = newController.value;
      final confirm = confirmController.value;

      if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
        error.value = 'Fill in all three fields.';
        return;
      }
      if (newPw.length < 10) {
        error.value = 'New password must be at least 10 characters.';
        return;
      }
      if (newPw != confirm) {
        error.value = 'New passwords do not match.';
        return;
      }
      if (newPw == current) {
        error.value = 'New password must be different from the current one.';
        return;
      }

      isLoading.value = true;
      error.value = null;

      final result = await di<IAuthRepository>().changePassword(
        ChangePasswordRequest(currentPassword: current, newPassword: newPw),
      );
      isLoading.value = false;

      switch (result) {
        case Success():
          if (context.mounted) {
            context.pop(true);
            ShadToaster.of(context).show(
              const ShadToast(
                title: Text('Password changed'),
                description: Text(
                  'Your password has been updated. Other devices have '
                  'been signed out.',
                ),
              ),
            );
          }
        case Failure(:final message):
          error.value = message;
      }
    }

    return ShadDialog.alert(
      title: const Text('CHANGE PASSWORD'),
      titleStyle: theme.textTheme.h1,
      description: const Padding(
        padding: .only(bottom: 16),
        child: Text(
          'Enter your current password and choose a new one. All other '
          'devices will be signed out.',
        ),
      ),
      descriptionTextAlign: .left,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          ShadInput(
            obscureText: true,
            placeholder: const Text('Current password'),
            onChanged: (v) => currentController.value = v,
          ),
          const SizedBox(height: 8),
          ShadInput(
            obscureText: true,
            placeholder: const Text('New password (min 10 characters)'),
            onChanged: (v) => newController.value = v,
          ),
          const SizedBox(height: 8),
          ShadInput(
            obscureText: true,
            placeholder: const Text('Confirm new password'),
            onChanged: (v) => confirmController.value = v,
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
      actionsAxis: .horizontal,
      expandActionsWhenTiny: false,
      actions: [
        ShadButton.outline(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          onPressed: isLoading.value ? null : () => context.pop(false),
          child: const Text('CANCEL'),
        ),
        ShadButton(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          enabled: !isLoading.value,
          onPressed: () => unawaited(submit()),
          child: isLoading.value ? const Spinner() : const Text('SAVE'),
        ),
      ],
    );
  }
}
