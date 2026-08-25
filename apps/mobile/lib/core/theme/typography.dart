import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// Builds the [FTypography] for the UniStash theme.
///
/// * **Display** → Archivo Narrow (condensed headings)
/// * **Body** → Inter (readable body copy)
/// * **Labels** → JetBrains Mono (monospace metadata — via [UsTypeface])
FTypography usTypography({
  required FColors colors,
  required bool touch,
}) =>
    FTypography(
      display: _display(colors: colors, touch: touch),
      body: _body(colors: colors, touch: touch),
    );

// ---------------------------------------------------------------------------
// Display — Archivo Narrow
// ---------------------------------------------------------------------------

/// Archivo Narrow: condensed sans-serif for display titles & headings.
///
/// Design-system mapping:
/// * xl2  → Display/Large  32/38  Bold
/// * xl   → Display/Medium 24/30  Bold
/// * lg   → Heading/Large  20/26  Bold
FTypeface _display({
  required FColors colors,
  required bool touch,
  String fontFamily = 'ArchivoNarrow',
  List<String>? fontFamilyFallback,
}) {
  assert(
    fontFamily.isNotEmpty,
    'fontFamily ($fontFamily) should not be empty.',
  );
  final color = colors.foreground;
  if (touch) {
    return FTypeface(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      xs3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 10,
        height: 1,
        leadingDistribution: .even,
      ),
      xs2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 12,
        height: 1,
        leadingDistribution: .even,
      ),
      xs: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 14,
        height: 18 / 14,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      sm: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      md: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      lg: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 24,
        height: 30 / 24,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 32,
        height: 38 / 32,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 36,
        height: 44 / 36,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl4: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 48,
        height: 56 / 48,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl5: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 60,
        height: 72 / 60,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl6: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 72,
        height: 84 / 72,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl7: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 96,
        height: 108 / 96,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl8: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 108,
        height: 120 / 108,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
    );
  } else {
    return FTypeface(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      xs3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 8,
        height: 1,
        leadingDistribution: .even,
      ),
      xs2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 10,
        height: 1,
        leadingDistribution: .even,
      ),
      xs: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 12,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      sm: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      md: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      lg: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 18,
        height: 1.75,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 20,
        height: 1.75,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 22,
        height: 2,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 30,
        height: 2.25,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl4: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 36,
        height: 2.5,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl5: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 48,
        height: 1,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl6: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 60,
        height: 1,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl7: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 72,
        height: 1,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
      xl8: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 96,
        height: 1,
        fontWeight: FontWeight.w700,
        leadingDistribution: .even,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — Inter
// ---------------------------------------------------------------------------

/// Inter: clean sans-serif for body copy, descriptions, and form content.
///
/// Design-system mapping:
/// * sm  → Body/Large  16/24  Regular
/// * xs  → Body/Medium 14/20  Regular
/// * xs2 → Body/Small  12/18  Regular
FTypeface _body({
  required FColors colors,
  required bool touch,
  String fontFamily = 'Inter',
  List<String>? fontFamilyFallback,
}) {
  assert(
    fontFamily.isNotEmpty,
    'fontFamily ($fontFamily) should not be empty.',
  );
  final color = colors.foreground;
  if (touch) {
    return FTypeface(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      xs3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 10,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xs2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 12,
        height: 18 / 12,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xs: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      sm: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      md: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 18,
        height: 28 / 18,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      lg: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 20,
        height: 30 / 20,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 22,
        height: 32 / 22,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 30,
        height: 40 / 30,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 36,
        height: 48 / 36,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl4: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 48,
        height: 56 / 48,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl5: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 60,
        height: 72 / 60,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl6: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 72,
        height: 84 / 72,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl7: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 96,
        height: 108 / 96,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl8: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 108,
        height: 120 / 108,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
    );
  } else {
    return FTypeface(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      xs3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 8,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xs2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 10,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xs: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 12,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      sm: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      md: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      lg: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 18,
        height: 1.75,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 20,
        height: 1.75,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl2: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 22,
        height: 2,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl3: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 30,
        height: 2.25,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl4: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 36,
        height: 2.5,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl5: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 48,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl6: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 60,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl7: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 72,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
      xl8: TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: 96,
        height: 1,
        fontWeight: FontWeight.w400,
        leadingDistribution: .even,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Labels & Captions — JetBrains Mono (accessed via UsTypeface)
// ---------------------------------------------------------------------------

/// Provides access to the JetBrains Mono label typeface.
///
/// ```dart
/// final label = context.theme.typography.us.label;
/// Text('CONDITION', style: label.md);
/// ```
extension UsTypefaceExtension on FTypography {
  UsTypeface get us => const UsTypeface();
}

/// JetBrains Mono: monospace font for metadata labels, field names,
/// status tags, prices, and small UI text.
class UsTypeface {
  const UsTypeface();

  String get _fontFamily => 'JetBrainsMono';

  /// Label/Large  · JetBrains Mono Regular · 14/20
  TextStyle get lg => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Label/Medium · JetBrains Mono Regular · 12/18
  TextStyle get md => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 18 / 12,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Caption/Medium · JetBrains Mono Regular · 12/16
  TextStyle get caption => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Label/Small · JetBrains Mono Regular · 10/14
  TextStyle get sm => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 10,
        height: 14 / 10,
        fontWeight: FontWeight.w400,
        leadingDistribution: TextLeadingDistribution.even,
      );
}
