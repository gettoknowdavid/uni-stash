import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// 404 page shown when the router encounters an unknown route.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return UsPage(
      header: const UsPageHeader(
        title: Text('NOT FOUND'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(UsSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '404',
                style: theme.textTheme.h1.copyWith(
                  fontSize: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: UsSpacing.md),
              Text(
                'Page not found',
                style: theme.textTheme.h3,
              ),
              const SizedBox(height: UsSpacing.sm),
              Text(
                "The page you're looking for doesn't exist or has been moved.",
                textAlign: .center,
                style: theme.textTheme.muted.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: UsSpacing.xl),
              ShadButton(
                onPressed: () => context.go(UsRoutes.home),
                child: const Text('GO HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
