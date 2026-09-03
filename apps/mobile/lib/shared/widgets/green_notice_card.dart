import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class GreenNoticeCard extends StatelessWidget {
  const GreenNoticeCard({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const .symmetric(horizontal: 16),
      child: ShadCard(
        padding: const .all(14),
        radius: const .all(.circular(UsRadius.lg)),
        border: ShadBorder.all(
          color: theme.colorScheme.borderStrong,
          radius: const .all(.circular(UsRadius.lg)),
          width: 2,
        ),
        backgroundColor: theme.colorScheme.statusSuccessBg,
        leading: const Icon(
          LucideIcons.shieldAlert,
          color: UsPrimitives.sage500,
        ),
        title: Padding(
          padding: const .only(left: 12),
          child: Text(
            title,
            style: theme.textTheme.labelLg.copyWith(
              color: UsPrimitives.sage500,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        description: Padding(
          padding: const .only(left: 12),
          child: Text(
            description,
            style: theme.textTheme.small.copyWith(
              color: UsPrimitives.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
