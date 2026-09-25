import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/blocks/view_models/blocked_users_view_model.dart';

/// Confirmation dialog that blocks [userId]. Pops with `true` on success so
/// the caller can refresh/back off. Best-effort toast on failure.
Future<void> showBlockUserDialog(
  BuildContext context, {
  required String userId,
  required String userName,
}) async {
  final confirmed = await showShadDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      title: Text('Block $userName?'),
      description: const Text(
        'You will no longer see their listings or be able to exchange '
        'messages. You can unblock later from Settings.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => dialogContext.pop(false),
          child: const Text('CANCEL'),
        ),
        ShadButton.destructive(
          onPressed: () => dialogContext.pop(true),
          child: const Text('BLOCK'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final ok = await blockUser(di, userId);
  if (!context.mounted) return;
  ShadToaster.of(context).show(
    ShadToast(
      title: Text(ok ? 'User blocked' : 'Could not block user'),
      description: Text(
        ok
            ? '$userName is blocked. Their listings are hidden from you.'
            : 'Please try again.',
      ),
    ),
  );
  if (ok) context.pop(true);
}
