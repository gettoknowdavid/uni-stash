import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class ConditionBadge extends StatelessWidget {
  const ConditionBadge({required this.condition, super.key});

  final Condition condition;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadDecorator(
      decoration: ShadDecoration(
        color: theme.colorScheme.muted,
        border: .all(color: theme.colorScheme.borderStrong),
      ),
      child: Padding(
        padding: const .symmetric(
          horizontal: UsSpacing.sm,
          vertical: UsSpacing.xxs,
        ),
        child: Text(
          condition.message,
          style: theme.textTheme.labelSm.copyWith(
            fontWeight: .w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
