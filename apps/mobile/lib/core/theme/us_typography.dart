import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// ---------------------------------------------------------------------------
// Design System Typography Tokens
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// UsLabelStyles — monospace labels and captions (ThemeExtension)
// ---------------------------------------------------------------------------

/// JetBrains Mono label and caption styles.
///
/// Access via `context.theme.us.typography`:
/// ```dart
/// Text('ACTIVE', style: context.theme.us.typography.labelLg);
/// ```
// @immutable
// class UsLabelStyles extends ThemeExtension<UsLabelStyles> {
//   const UsLabelStyles({
//     required this.labelLg,
//     required this.labelMd,
//     required this.labelSm,
//     required this.captionMd,
//   });

//   /// Default instance using the foreground color from the current theme.
//   factory UsLabelStyles.withForeground(Color foreground) {
//     return UsLabelStyles(
//       labelLg: TextStyle(
//         fontFamily: UsFontFamily.mono,
//         fontSize: 14,
//         height: 20 / 14,
//         fontWeight: FontWeight.w400,
//         letterSpacing: 0.5,
//         color: foreground,
//         leadingDistribution: TextLeadingDistribution.even,
//       ),
//       labelMd: TextStyle(
//         fontFamily: UsFontFamily.mono,
//         fontSize: 12,
//         height: 18 / 12,
//         fontWeight: FontWeight.w400,
//         letterSpacing: 0.5,
//         color: foreground,
//         leadingDistribution: TextLeadingDistribution.even,
//       ),
//       labelSm: TextStyle(
//         fontFamily: UsFontFamily.mono,
//         fontSize: 10,
//         height: 14 / 10,
//         fontWeight: FontWeight.w400,
//         letterSpacing: 0.5,
//         color: foreground,
//         leadingDistribution: TextLeadingDistribution.even,
//       ),
//       captionMd: TextStyle(
//         fontFamily: UsFontFamily.mono,
//         fontSize: 12,
//         height: 16 / 12,
//         fontWeight: FontWeight.w400,
//         color: foreground,
//         leadingDistribution: TextLeadingDistribution.even,
//       ),
//     );
//   }

//   /// Label/Large · JetBrains Mono Regular · 14/20 · +0.5px tracking
//   final TextStyle labelLg;

//   /// Label/Medium · JetBrains Mono Regular · 12/18 · +0.5px tracking
//   final TextStyle labelMd;

//   /// Label/Small · JetBrains Mono Regular · 10/14 · +0.5px tracking
//   final TextStyle labelSm;

//   /// Caption/Medium · JetBrains Mono Regular · 12/16 · 0px tracking
//   final TextStyle captionMd;

//   UsLabelStyles copyWith({
//     TextStyle? labelLg,
//     TextStyle? labelMd,
//     TextStyle? labelSm,
//     TextStyle? captionMd,
//   }) {
//     return UsLabelStyles(
//       labelLg: labelLg ?? this.labelLg,
//       labelMd: labelMd ?? this.labelMd,
//       labelSm: labelSm ?? this.labelSm,
//       captionMd: captionMd ?? this.captionMd,
//     );
//   }

//   UsLabelStyles lerp(covariant UsLabelStyles? other, double t) {
//     if (other is! UsLabelStyles) return this;
//     return UsLabelStyles(
//       labelLg: TextStyle.lerp(labelLg, other.labelLg, t)!,
//       labelMd: TextStyle.lerp(labelMd, other.labelMd, t)!,
//       labelSm: TextStyle.lerp(labelSm, other.labelSm, t)!,
//       captionMd: TextStyle.lerp(captionMd, other.captionMd, t)!,
//     );
//   }

//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is UsLabelStyles &&
//           runtimeType == other.runtimeType &&
//           labelLg == other.labelLg &&
//           labelMd == other.labelMd &&
//           labelSm == other.labelSm &&
//           captionMd == other.captionMd;

//   @override
//   int get hashCode => Object.hash(labelLg, labelMd, labelSm, captionMd);
// }

// ---------------------------------------------------------------------------
// Build the ShadTextTheme for UniStash
// ---------------------------------------------------------------------------

/// Creates a [ShadTextTheme] with the design system's three-font stack.
///
/// * Headings → Archivo Narrow
/// * Body → Inter
/// * Labels → JetBrains Mono (via [UsLabelStyles] ThemeExtension)
ShadTextTheme usTextTheme({required Color foreground}) {
  final color = foreground;

  // ── Heading styles (Archivo Narrow) ────────────────────────────────────────

  /// h1Large → Display/Large · 32/38 · Bold · +0.5px tracking
  final h1Large = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h1 → Display/Medium · 24/30 · Bold · +0.3px tracking
  final h1 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h2 → Heading/Large · 20/26 · Bold · 0px tracking
  final h2 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h3 → Heading/Medium · 18/24 · Bold · 0px tracking
  final h3 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// h4 → Heading/Small · 16/22 · Bold · 0px tracking
  final h4 = TextStyle(
    fontFamily: UsFontFamily.display,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w700,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // ── Body styles (Inter) ────────────────────────────────────────────────────

  /// p → Body/Large · 16/24 · Regular
  final p = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// lead → Body/Medium · 14/20 · Regular
  final lead = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// small → Body/Small · 12/18 · Regular
  final small = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// muted → Helper text · 14/20 · Regular
  final muted = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // ── Misc styles (Inter default) ────────────────────────────────────────────

  final blockquote = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final table = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w700,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final list = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final large = TextStyle(
    fontFamily: UsFontFamily.body,
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w600,
    color: color,
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
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: foreground,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      'labelMd': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 12,
        height: 18 / 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: foreground,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      'labelSm': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 10,
        height: 14 / 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: foreground,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      'captionMd': TextStyle(
        fontFamily: UsFontFamily.mono,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: foreground,
        leadingDistribution: TextLeadingDistribution.even,
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
