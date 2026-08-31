import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'package:uni_stash_mobile/core/theme/colors.dart';

/// Builds [FButtonStyles] with UniStash primary button customizations.
///
/// The primary variant maps each interactive state to exact design-system
/// tokens:
///
/// | State    | Background          | Foreground        |
/// |----------|---------------------|-------------------|
/// | Default  | orange/500 #FF5B1F  | white #FFFFFF     |
/// | Hover    | orange/200 #D17A5D  | white #FFFFFF     |
/// | Pressed  | brown/500  #5B4138  | white #FFFFFF     |
/// | Disabled | neutral/400 #E3E2DF | neutral/500       |
/// | Focus    | orange/500 + dark outline |
///
/// All primary button shapes use pill border radius per the design spec.
/// Secondary / destructive / outline / ghost inherit from Forui defaults.
FButtonStyles usButtonStyles({
  required FColors colors,
  required FTypography typography,
  required FStyle style,
  required bool touch,
}) {
  // ── Custom primary variant ──────────────────────────────────────────────
  // Uses exact design-system tokens instead of Forui's computed hover/disable.
  // Ignores the per-size radius parameter and forces pill shape.
  final usPrimary = FButtonSizeStyles.inherit(
    typography: typography,
    style: style,
    touch: touch,
    decoration: (_) => FVariants.from(
      ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.sm),
        color: colors.primary, // #FF5B1F — Default
      ),
      variants: {
        [.hovered]: .shapeDelta(color: colors.us.actionPrimaryHover),
        // #D17A5D
        [.pressed]: .shapeDelta(color: colors.us.actionPrimaryPressed),
        // #5B4138
        [.disabled]: .shapeDelta(color: colors.us.actionDisabled),
        // #E3E2DF
        [.selected]: .shapeDelta(color: colors.us.actionPrimaryHover),
        [.selected.and(.disabled)]: .shapeDelta(
          color: colors.disable(colors.us.actionPrimaryHover),
        ),
        [.focused]: .shapeDelta(
          color: colors.primary,
          shape: BeveledRectangleBorder(
            borderRadius: style.borderRadius.sm,
            side: BorderSide(color: colors.us.borderStrong),
          ),
        ),
      },
    ),
    foregroundColor: colors.primaryForeground,
    disabledForegroundColor: colors.us.textDisabled,
  );

  // ── Inherited styles for secondary / destructive / outline / ghost ─────
  final inherited = FButtonStyles.inherit(
    colors: colors,
    typography: typography,
    style: style,
    touch: touch,
  );

  // ── Assemble: custom primary + inherited others ───────────────────────
  return FButtonStyles(
    FVariants(
      usPrimary,
      variants: {
        [.primary]: usPrimary,
        [.secondary]: inherited.resolve({FButtonVariant.secondary}),
        [.destructive]: inherited.resolve({FButtonVariant.destructive}),
        [.outline]: inherited.resolve({FButtonVariant.outline}),
        [.ghost]: inherited.resolve({FButtonVariant.ghost}),
      },
    ),
  );
}
