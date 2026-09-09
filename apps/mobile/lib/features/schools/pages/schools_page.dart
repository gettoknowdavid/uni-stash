import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class SchoolsPage extends StatelessWidget {
  const SchoolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return UsPage(
      header: const UsPageHeader(title: Text('SCHOOLS')),
      body: Center(
        child: Text(
          'Schools listing coming soon',
          style: theme.textTheme.muted.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}
