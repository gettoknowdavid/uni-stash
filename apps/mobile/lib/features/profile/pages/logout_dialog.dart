import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';

class LogoutDialog extends StatelessWidget {
  const LogoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 48,
            color: theme.colorScheme.destructive,
          ),
          const SizedBox(height: 16),
          Text(
            'LOG OUT?',
            textAlign: .center,
            style: theme.textTheme.h2,
          ),
          const SizedBox(height: 12),
          Text(
            'Are you sure you want to log out of UniStash?',
            textAlign: .center,
            style: theme.textTheme.p.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CANCEL'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShadButton.destructive(
                  onPressed: () => _logout(context),
                  child: const Text('LOG OUT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    // Close the dialog first.
    Navigator.of(context).pop();
    // Trigger unauthentication — the router's redirect will bounce to /login.
    di<AuthViewModel>().unauthenticate();
    // Navigate to login, clearing the navigation stack.
    context.go(UsRoutes.login);
  }
}
