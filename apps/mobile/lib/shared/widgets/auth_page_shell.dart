import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/style.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';
import 'package:uni_stash_mobile/theme/us_typography.dart';

/// A reusable shell for authentication pages (login, sign-up, etc.).
///
/// Renders the standard "brutalist" bordered container with the
/// UNI·STASH title and "Campus Bulletin Board" subtitle, plus an
/// optional [footer] widget (e.g. "Already have an account?" link).
class AuthPageShell extends StatelessWidget {
  const AuthPageShell({
    required this.title,
    required this.body,
    this.subtitle,
    this.description,
    this.footer,
    this.bodyFooterSpacing = 16,
    super.key,
  });

  /// The title displayed at the top of the shell.
  final Widget title;

  /// The subtitle displayed below the title.
  final Widget? subtitle;

  /// The description displayed below the subtitle.
  final Widget? description;

  /// The form content displayed below the title/subtitle.
  final Widget body;

  /// Optional footer widget (e.g. a navigation row) displayed at the bottom
  /// of the shell, separated by a spacer.
  final Widget? footer;

  /// The spacing between the body and footer widgets.
  final double bodyFooterSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceAccentSubtle,
        borderRadius: .zero,
        border: Border.all(
          color: theme.colorScheme.borderStrong,
          width: 2,
        ),
        boxShadow: UsElevation.brutalist,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: theme.textTheme.h1Large.copyWith(
              color: theme.colorScheme.foreground,
              letterSpacing: -1.6,
            ),
            child: title,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: TextStyle(
                fontFamily: UsFontFamily.mono,
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: .bold,
                decoration: .underline,
                decorationColor: theme.colorScheme.primary,
                decorationThickness: 2,
                height: 1,
                letterSpacing: 0.6,
              ),
              child: subtitle!,
            ),
          ],
          if (description != null) ...[
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: theme.textTheme.muted.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
              child: description!,
            ),
          ],

          const SizedBox(height: 24),
          body,
          if (footer != null) ...[
            SizedBox(height: bodyFooterSpacing),
            footer!,
          ],
        ],
      ),
    );
  }
}
