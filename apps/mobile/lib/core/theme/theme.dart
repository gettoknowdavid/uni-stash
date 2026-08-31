import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'package:uni_stash_mobile/core/theme/colors.dart';
import 'package:uni_stash_mobile/core/theme/style.dart';
import 'package:uni_stash_mobile/core/theme/styles/button_style.dart';
import 'package:uni_stash_mobile/core/theme/styles/text_field_style.dart';
import 'package:uni_stash_mobile/core/theme/typography.dart';

/// UniStash light theme.
///
/// Usage:
/// ```dart
/// FTheme(
///   data: usLightTheme,
///   child: FToaster(child: FTooltipGroup(child: child!)),
/// )
/// ```
FThemeData get usLightTheme {
  const touch = true;

  // ── Core tokens ──────────────────────────────────────────────────────────
  final colors = usLightColors;
  final typography = usTypography(colors: colors, touch: touch);
  final style = usStyle(colors: colors, typography: typography);

  // ── Button styles ──────────────────────────────────────────────────────
  // Custom primary variant with exact design-system colors + pill shape.
  // Secondary/ghost/outline/destructive inherit from Forui defaults.
  final buttonStyles = usButtonStyles(
    colors: colors,
    typography: typography,
    style: style,
    touch: touch,
  );

  // ── Text field styles ──────────────────────────────────────────────────
  final iconStyle = usIconStyle(colors: colors, typography: typography);
  final ghostForTff = buttonStyles.ghost.sm.copyWith(
    iconContentStyle: buttonStyles.ghost.sm.iconContentStyle.copyWith(
      iconStyle: iconStyle.cast(),
    ),
  );

  final tffBase = usTextFieldStyle(
    colors: colors,
    style: style,
    typography: typography,
    iconStyle: iconStyle,
    buttonStyle: ghostForTff,
    constraints: const BoxConstraints(minHeight: 44),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  // ── Assemble FThemeData ────────────────────────────────────────────────
  return FThemeData(
    colors: colors,
    typography: typography,
    icons: const FIcons.lucide(),
    style: style,
    touch: touch,

    // Custom primary (pill, exact colors) + inherited secondary/ghost/outline
    buttonStyles: buttonStyles,

    // Text field styles — custom UniStash appearance
    textFieldStyles: FTextFieldSizeStyles(
      FVariants(
        tffBase,
        variants: {
          [.sm]: tffBase.copyWith(
            constraints: const BoxConstraints(minHeight: 40),
            contentPadding: const EdgeInsetsGeometryDelta.value(
              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          [.md]: tffBase,
          [.lg]: tffBase.copyWith(
            constraints: const BoxConstraints(minHeight: 48),
            contentPadding: const EdgeInsetsGeometryDelta.value(
              EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        },
      ),
    ),

    // Modal sheet — brutalist border + shadow
    modalSheetStyle: FModalSheetStyle.inherit(),
  );
}

/// Icon style variant factory for text field clear/obscure buttons.
FVariants<
  FTextFieldVariantConstraint,
  FTextFieldVariant,
  IconThemeData,
  IconThemeDataDelta
>
usIconStyle({
  required FColors colors,
  required FTypography typography,
}) {
  return FVariants<
    FTextFieldVariantConstraint,
    FTextFieldVariant,
    IconThemeData,
    IconThemeDataDelta
  >.from(
    IconThemeData(
      color: colors.mutedForeground,
      size: typography.body.sm.fontSize,
      weight: 200,
    ),
    variants: {
      [.disabled]: IconThemeDataDelta.delta(
        color: colors.disable(colors.mutedForeground),
      ),
    },
  );
}
