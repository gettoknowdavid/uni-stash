import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Font family constants matching the pubspec.yaml registration.
abstract final class UsFontFamily {
  const UsFontFamily._();

  /// Archivo Narrow — condensed sans-serif for headings.
  static const String display = 'ArchivoNarrow';

  /// Inter — clean sans-serif for body copy.
  static const String body = 'Inter';

  /// JetBrains Mono — monospace for labels and metadata.
  static const String mono = 'JetBrainsMono';
}

/// Creates a [ShadTextTheme] with the design system's three-font stack.
///
/// * Headings → Archivo Narrow
/// * Body → Inter
/// * Labels → JetBrains Mono
ShadTextTheme usTextTheme(ShadColorScheme colors) {
  // ── Heading styles (Archivo Narrow) ────────────────────────────────────────

  /// h1Large → Display/Large · 32/38 · Bold · +0.5px tracking
  final h1Large = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 32,
    height: 38 / 32,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h1 → Display/Medium · 24/30 · Bold · +0.3px tracking
  final h1 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 24,
    height: 30 / 24,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h2 → Heading/Large · 20/26 · Bold · 0px tracking
  final h2 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 20,
    height: 26 / 20,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h3 → Heading/Medium · 18/24 · Bold · 0px tracking
  final h3 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 18,
    height: 24 / 18,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h4 → Heading/Small · 16/22 · Bold · 0px tracking
  final h4 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 16,
    height: 22 / 16,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // ── Body styles (Inter) ────────────────────────────────────────────────────

  /// p → Body/Large · 16/24 · Regular
  final p = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    color: colors.foreground,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// lead → Body/Medium · 14/20 · Regular
  final lead = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 14,
    height: 20 / 14,
    color: colors.foreground,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// small → Body/Small · 12/18 · Regular
  final small = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 12,
    height: 18 / 12,
    color: colors.foreground,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// muted → Helper text · 14/20 · Regular
  final muted = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 14,
    height: 20 / 14,
    color: colors.mutedForeground,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // ── Misc styles (Inter default) ────────────────────────────────────────────

  final blockquote = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    color: colors.foreground,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final table = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    color: colors.foreground,
    fontWeight: FontWeight.w700,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final list = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    color: colors.foreground,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final large = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 18,
    height: 28 / 18,
    color: colors.foreground,
    fontWeight: FontWeight.w600,
    leadingDistribution: TextLeadingDistribution.even,
  );

  return ShadTextTheme.custom(
    h1Large: h1Large,
    h1: h1,
    h2: h2,
    h3: h3,
    h4: h4,
    p: p,
    blockquote: blockquote,
    table: table,
    list: list,
    lead: lead,
    large: large,
    small: small,
    muted: muted,
    family: UsFontFamily.body, // default family for anything unspecified
    custom: {
      'labelLg': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 14,
        height: 20 / 14,
        color: colors.foreground,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: .none,
      ),
      'labelMd': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 12,
        height: 18 / 12,
        color: colors.foreground,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: .none,
      ),
      'labelSm': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 10,
        height: 14 / 10,
        color: colors.foreground,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: .none,
      ),
      'captionMd': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 12,
        height: 16 / 12,
        color: colors.foreground,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: .none,
      ),
    },
  );
}

extension CustomShadTextTheme on ShadTextTheme {
  TextStyle get labelLg => custom['labelLg'] ?? const TextStyle();
  TextStyle get labelMd => custom['labelMd'] ?? const TextStyle();
  TextStyle get labelSm => custom['labelSm'] ?? const TextStyle();
  TextStyle get captionMd => custom['captionMd'] ?? const TextStyle();
}
