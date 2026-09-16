import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final (label, bgColor, fgColor) = switch (status) {
      ListingStatus.active => (
        'ACTIVE',
        UsPrimitives.sage100,
        UsPrimitives.neutralBlack,
      ),
      ListingStatus.reserved => (
        'RESERVED',
        theme.colorScheme.foreground,
        theme.colorScheme.background,
      ),
      ListingStatus.sold => (
        'SOLD',
        theme.colorScheme.muted,
        theme.colorScheme.mutedForeground,
      ),
      ListingStatus.deleted => (
        'DELETED',
        theme.colorScheme.destructive,
        theme.colorScheme.destructiveForeground,
      ),
    };

    return ShadDecorator(
      decoration: ShadDecoration(
        color: bgColor,
        border: .all(color: theme.colorScheme.borderStrong),
      ),
      child: Padding(
        padding: const .symmetric(
          horizontal: UsSpacing.sm,
          vertical: UsSpacing.xxs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSm.copyWith(
            color: fgColor,
            fontWeight: .w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
