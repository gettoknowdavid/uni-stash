import 'dart:ui';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uni_stash_mobile/core/theme/styles/form_field_style.dart';

// ---------------------------------------------------------------------------
// Spacing tokens (Base-4)
// ---------------------------------------------------------------------------

/// Base-4 spatial scale used for padding, margins, and gaps.
///
/// The 16px unit is the most common spacing value across the app.
abstract final class UsSpacing {
  const UsSpacing._();

  /// Micro adjustments
  static const double xxs = 2;

  /// Extra tight
  static const double xs = 4;

  /// Tight (sub-sections)
  static const double sm = 8;

  /// Compact (nested controls)
  static const double md = 12;

  /// Standard (card padding)
  static const double lg = 16;

  /// Relaxed (sections)
  static const double xl = 24;

  /// Loose (top margins)
  static const double xxl = 32;

  /// Hero spacer
  static const double xxxl = 48;

  /// Page floor
  static const double huge = 96;
}

// ---------------------------------------------------------------------------
// Radius tokens
// ---------------------------------------------------------------------------

/// Corner radius tokens from sharp to fully rounded.
///
/// The design uses sm (4px) for buttons/inputs, md (8px) for badges/minor
/// cards, lg (12px) for grid items/listing cards, xl (16px) for large modals,
/// and full (9999px) for pill badges, toggles, and circles.
abstract final class UsRadius {
  const UsRadius._();

  /// Hard corners (0px) — checkboxes, square icons
  static const double none = 0;

  /// Buttons, input fields, subtle panels (4px)
  static const double sm = 4;

  /// Badges, minor cards (8px)
  static const double md = 8;

  /// Grid items, main listing cards (12px)
  static const double lg = 12;

  /// Large modal containers (16px)
  static const double xl = 16;

  /// Pill badges, toggles, circles (9999px)
  static const double full = 9999;
}

// ---------------------------------------------------------------------------
// Elevation (Drop Shadow) tokens
// ---------------------------------------------------------------------------

/// Box shadow presets matching the design system elevation scale.
abstract final class UsElevation {
  const UsElevation._();

  /// sm: 0px 1px 3px rgba(0,0,0,0.05) — Subtle card depth
  static const List<BoxShadow> sm = [
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color(0x0D000000), // 5%
    ),
  ];

  /// md: 0px 4px 8px -2px rgba(0,0,0,0.06), 0px 1px 2px rgba(0,0,0,0.04)
  static const List<BoxShadow> md = [
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 8,
      spreadRadius: -2,
      color: Color(0x0F000000), // 6%
    ),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      color: Color(0x0A000000), // 4%
    ),
  ];

  /// lg: 0px 10px 24px -4px rgba(0,0,0,0.08), 0px 4px 6px rgba(0,0,0,0.04)
  static const List<BoxShadow> lg = [
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 24,
      spreadRadius: -4,
      color: Color(0x14000000), // 8%
    ),
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 6,
      color: Color(0x0A000000), // 4%
    ),
  ];

  /// xl: 0px 20px 40px -8px rgba(0,0,0,0.12), 0px 8px 12px rgba(0,0,0,0.04)
  static const List<BoxShadow> xl = [
    BoxShadow(
      offset: Offset(0, 20),
      blurRadius: 40,
      spreadRadius: -8,
      color: Color(0x1F000000), // 12%
    ),
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 12,
      color: Color(0x0A000000), // 4%
    ),
  ];

  /// Brutalist thick shadow — used on dialogs and elevated surfaces.
  /// 4px 4px 0px neutral/900
  static const List<BoxShadow> brutalist = [
    BoxShadow(
      offset: Offset(4, 4),
      color: Color(0xFF15140F),
    ),
  ];
}

// ---------------------------------------------------------------------------
// FStyle builder
// ---------------------------------------------------------------------------

/// Builds [FStyle] with UniStash spacing and radius tokens.
FStyle usStyle({
  required FColors colors,
  required FTypography typography,
}) {
  return FStyle(
    formFieldStyle: formFieldStyle(
      colors: colors,
      touch: true,
      typography: typography,
    ),
    focusedOutlineStyle: FFocusedOutlineStyle(
      color: colors.primary,
      borderRadius: BorderRadius.circular(UsRadius.sm),
    ),
    sizes: FSizes.inherit(touch: true),
    iconStyle: IconThemeData(
      color: colors.foreground,
      size: typography.body.lg.fontSize,
    ),
    tappableStyle: FTappableStyle(),
    borderRadius: FBorderRadius(
      xs2: BorderRadius.circular(UsRadius.none),
      xs: BorderRadius.circular(UsRadius.none),
      sm: BorderRadius.circular(UsRadius.none),
      md: BorderRadius.circular(UsRadius.none),
      lg: BorderRadius.circular(UsRadius.none),
      xl: BorderRadius.circular(UsRadius.none),
      xl2: BorderRadius.circular(UsRadius.none),
      xl3: BorderRadius.circular(UsRadius.none),
      // xs2: BorderRadius.circular(UsRadius.sm),
      // xs: BorderRadius.circular(UsRadius.sm),
      // sm: BorderRadius.circular(UsRadius.sm),
      // md: BorderRadius.circular(UsRadius.md),
      // lg: BorderRadius.circular(UsRadius.lg),
      // xl: BorderRadius.circular(UsRadius.xl),
      // xl2: BorderRadius.circular(UsRadius.xl),
      // xl3: BorderRadius.circular(UsRadius.xl),
      pill: BorderRadius.circular(UsRadius.sm),
    ),
    borderWidth: 2,
    extensions: [const UsStyle()],
  );
}

// ---------------------------------------------------------------------------
// UsStyle — custom design system style tokens
// ---------------------------------------------------------------------------

/// Provides convenient access via `context.theme.style.us`.
extension FStyleExtensions on FStyle {
  UsStyle get us => extension<UsStyle>();
}

/// Additional style tokens specific to the UniStash design system.
///
/// Access through [FStyleExtensions]:
/// ```dart
/// final shadows = context.theme.style.us.elevationMd;
/// final radius = context.theme.style.us.cardRadius;
/// ```
@immutable
class UsStyle extends ThemeExtension<UsStyle> {
  const UsStyle({
    this.borderWidthStrong = 2,
    this.borderWidthDefault = 1,
  });

  /// Heavy border width for buttons and brutalist elements.
  final double borderWidthStrong;

  /// Default border width for inputs and cards.
  final double borderWidthDefault;

  @override
  UsStyle copyWith({double? borderWidthStrong, double? borderWidthDefault}) =>
      UsStyle(
        borderWidthStrong: borderWidthStrong ?? this.borderWidthStrong,
        borderWidthDefault: borderWidthDefault ?? this.borderWidthDefault,
      );

  @override
  UsStyle lerp(covariant UsStyle? other, double t) {
    if (other is! UsStyle) return this;
    return UsStyle(
      borderWidthStrong: lerpDouble(
        borderWidthStrong,
        other.borderWidthStrong,
        t,
      )!,
      borderWidthDefault: lerpDouble(
        borderWidthDefault,
        other.borderWidthDefault,
        t,
      )!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsStyle &&
          runtimeType == other.runtimeType &&
          borderWidthStrong == other.borderWidthStrong &&
          borderWidthDefault == other.borderWidthDefault;

  @override
  int get hashCode =>
      Object.hash(runtimeType, borderWidthStrong, borderWidthDefault);
}
