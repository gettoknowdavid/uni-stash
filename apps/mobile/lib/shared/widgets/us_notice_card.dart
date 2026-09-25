import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Semantic variants of [UsNoticeCard]. Each maps to a background tint,
/// foreground accent and a default icon from the UniStash palette, so the
/// card reads correctly as success / warning / info / danger.
enum UsNoticeVariant {
  /// Sage-tinted reassurance (e.g. "verified students only" messaging).
  success(
    background: UsPrimitives.sage100,
    foreground: UsPrimitives.sage500,
    icon: LucideIcons.shieldCheck,
  ),

  /// Amber/orange-tinted caution (e.g. safety tips before a meetup).
  warning(
    background: UsPrimitives.orange100,
    foreground: UsPrimitives.brown500,
    icon: LucideIcons.triangleAlert,
  ),

  /// Blue-tinted neutral information.
  info(
    background: UsPrimitives.blue100,
    foreground: UsPrimitives.blue500,
    icon: LucideIcons.info,
  ),

  /// Red-tinted strong caution (use sparingly — real danger).
  danger(
    background: UsPrimitives.red100,
    foreground: UsPrimitives.red500,
    icon: LucideIcons.octagonAlert,
  );

  const UsNoticeVariant({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
}

/// A tinted inline notice card used for safety tips, warnings and other
/// short guidance blocks. Replaces the old single-purpose
/// `GreenNoticeCard` — same slot in the layout, but variant, icon, title
/// and body are all customizable.
///
/// ```dart
/// const UsNoticeCard(
///   variant: UsNoticeVariant.warning,
///   title: 'STAY SAFE',
///   description: 'Meet in public places and inspect items before paying.',
/// )
/// ```
class UsNoticeCard extends StatelessWidget {
  const UsNoticeCard({
    required this.title,
    required this.description,
    this.variant = UsNoticeVariant.success,
    this.icon,
    this.items,
    super.key,
  });

  /// Short, bold headline (e.g. "SAFETY TIPS").
  final String title;

  /// Supporting sentence(s) shown under the title.
  final String description;

  /// Visual/semantic tone of the card.
  final UsNoticeVariant variant;

  /// Optional icon override; defaults to the variant's icon.
  final IconData? icon;

  /// Optional bullet list rendered under [description] (e.g. safety tips).
  final List<String>? items;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final iconData = icon ?? variant.icon;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ShadCard(
        padding: const EdgeInsets.all(14),
        radius: const BorderRadius.all(Radius.circular(UsRadius.lg)),
        border: ShadBorder.all(
          color: variant.foreground.withValues(alpha: 0.35),
          radius: const BorderRadius.all(Radius.circular(UsRadius.lg)),
          width: 2,
        ),
        backgroundColor: variant.background,
        leading: Icon(iconData, color: variant.foreground),
        title: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            title,
            style: theme.textTheme.labelLg.copyWith(
              color: variant.foreground,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        description: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: theme.textTheme.small.copyWith(
                  color: UsPrimitives.neutral900.withValues(alpha: 0.8),
                ),
              ),
              if (items != null && items!.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final item in items!)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(
                            LucideIcons.dot,
                            size: 14,
                            color: variant.foreground,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item,
                            style: theme.textTheme.small.copyWith(
                              color: UsPrimitives.neutral900
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
