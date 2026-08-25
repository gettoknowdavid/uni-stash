import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// Spacing tokens
// ---------------------------------------------------------------------------

/// Base-4 spatial scale used for padding, margins, and gaps.
///
/// The 16px unit is the most common spacing value across the app.
abstract final class UsSpacing {
  const UsSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 96;
}

// ---------------------------------------------------------------------------
// Radius tokens
// ---------------------------------------------------------------------------

/// Corner radius tokens from sharp to fully rounded.
///
/// The design primarily uses 4px for subtle rounding and 9999px (full) for
/// pill-shaped elements like buttons and badges.
abstract final class UsRadius {
  const UsRadius._();

  static const double none = 0;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 9999;
}

// ---------------------------------------------------------------------------
// FStyle builder
// ---------------------------------------------------------------------------

/// Builds [FStyle] with UniStash spacing and radius tokens.
FStyle usStyle({
  required FColors colors,
  required FTypography typography,
  required bool touch,
}) {
  const borderRadius = FBorderRadius();
  return FStyle(
    formFieldStyle: .inherit(
      colors: colors,
      typography: typography,
      touch: touch,
    ),
    focusedOutlineStyle: FFocusedOutlineStyle(
      color: colors.primary,
      borderRadius: borderRadius.md,
    ),
    sizes: FSizes.inherit(touch: touch),
    iconStyle: IconThemeData(
      color: colors.foreground,
      size: typography.body.lg.fontSize,
    ),
    tappableStyle: FTappableStyle(),
    extensions: [const UsStyle()],
  );
}

// ---------------------------------------------------------------------------
// UsStyle — custom style tokens
// ---------------------------------------------------------------------------

/// Provides convenient access via `context.theme.style.us`.
extension FStyleExtensions on FStyle {
  UsStyle get us => extension<UsStyle>();
}

/// Additional style tokens specific to the UniStash design system.
///
/// Access through [FStyleExtensions]:
/// ```dart
/// final radius = context.theme.style.us.cardRadius;
/// ```
@immutable
class UsStyle extends ThemeExtension<UsStyle> {
  const UsStyle();

  @override
  UsStyle copyWith() => const UsStyle();

  @override
  UsStyle lerp(covariant UsStyle? other, double t) {
    if (other is! UsStyle) return this;
    return const UsStyle();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsStyle && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
