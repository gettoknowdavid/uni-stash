import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';

/// REPORT USER dialog: flags a user for moderation via
/// `POST /reports/users/{user_id}`. Idempotent per (reporter, user).
class ReportUserDialog extends SignalHookWidget {
  const ReportUserDialog({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final reason = useSignal('');
    final isLoading = useSignal(false);
    final error = useSignal<String?>(null);

    Future<void> submit() async {
      isLoading.value = true;
      error.value = null;

      try {
        await di<Dio>().post<dynamic>(
          '/api/v1/reports/users/$userId',
          data: {
            'reason': reason.value.trim().isEmpty ? null : reason.value.trim(),
          },
        );
        if (context.mounted) {
          context.pop(true);
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('Reported'),
              description: Text(
                'Thank you. Our team will review this user.',
              ),
            ),
          );
        }
      } on DioException catch (e) {
        isLoading.value = false;
        final failure = dioFailure<void>(e);
        error.value = switch (failure) {
          Failure(:final message) => message,
          _ => 'An unexpected error occurred.',
        };
      } on Object {
        isLoading.value = false;
        error.value = 'An unexpected error occurred.';
      }
    }

    return ShadDialog.alert(
      title: const Text('REPORT USER'),
      titleStyle: theme.textTheme.h1,
      description: const Padding(
        padding: .only(bottom: 16),
        child: Text(
          'Tell us what this user did. Reports are reviewed by the '
          'UniStash team and are anonymous to the reported user.',
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
          child: isLoading.value ? const Spinner() : const Text('REPORT'),
        ),
      ],
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          ShadInput(
            placeholder: const Text(
              'e.g. Scam attempt, harassment, fake profile...',
            ),
            maxLines: 3,
            minLines: 2,
            onChanged: (v) => reason.value = v,
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
