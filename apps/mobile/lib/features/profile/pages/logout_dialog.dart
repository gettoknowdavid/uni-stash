import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/scope.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class LogoutDialog extends SignalHookWidget {
  const LogoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final isLoading = useSignal(false);

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
          onPressed: isLoading.value ? null : () => context.pop(false),
          child: const Text('CANCEL'),
        ),
        ShadButton(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          enabled: !isLoading.value,
          onPressed: () async {
            isLoading.value = true;

            di<AuthViewModel>().unauthenticate();

            if (di.hasScope(Scope.root)) {
              await di.popScopesTill(Scope.root, inclusive: false);
            }

            if (context.mounted) context.go(UsRoutes.login);
          },
          child: isLoading.value ? const Spinner() : const Text('LOG OUT'),
        ),
      ],
    );
  }
}
