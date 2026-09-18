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
    return ShadDialog.alert(
      padding: const .fromLTRB(24, 0, 24, 24),
      title: const Text('LOGOUT?'),
      titleStyle: theme.textTheme.h1,
      titleTextAlign: .center,
      description: const Padding(
        padding: .only(bottom: 24),
        child: Text('Are you sure you want to logout of UniStash?'),
      ),
      descriptionTextAlign: .center,
      actionsAxis: .horizontal,
      expandActionsWhenTiny: false,
      actions: [
        ShadButton.outline(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          child: const Text('CANCEL'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ShadButton(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          onPressed: () => _logout(context),
          child: const Text('LOG OUT'),
        ),
      ],
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
