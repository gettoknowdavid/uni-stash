import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:uni_stash_mobile/theme/style.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';
import 'package:uni_stash_mobile/theme/us_typography.dart';

/// UniStash light theme built on top of [ShadThemeData].
///
/// Usage:
/// ```dart
/// ShadApp(
///   theme: usLightTheme,
/// )
/// ```
ShadThemeData get usLightTheme {
  // ── Color scheme ─────────────────────────────────────────────────────────
  final colorScheme = UniStashColorScheme.light();

  // ── Typography ───────────────────────────────────────────────────────────
  final textTheme = usTextTheme();

  // ── Global border radius: sm (4px) ──────────────────────────────────────
  const effectiveRadius = BorderRadius.zero;

  // ── Primary button theme — orange fill, white text, 4px radius ──────────
  final primaryButtonTheme = ShadButtonTheme(
    backgroundColor: UsPrimitives.orange500,
    hoverBackgroundColor: UsPrimitives.orange200,
    pressedBackgroundColor: UsPrimitives.brown500,
    foregroundColor: UsPrimitives.neutralWhite,
    hoverForegroundColor: UsPrimitives.neutralWhite,
    pressedForegroundColor: UsPrimitives.neutralWhite,
    textStyle: const TextStyle(
      fontFamily: UsFontFamily.display,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 0,
    ),
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        color: UsPrimitives.orange500,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Secondary button theme — dark brutalist fill ────────────────────────
  final secondaryButtonTheme = ShadButtonTheme(
    backgroundColor: UsPrimitives.neutral900,
    hoverBackgroundColor: UsPrimitives.neutral800,
    pressedBackgroundColor: UsPrimitives.neutral800,
    foregroundColor: UsPrimitives.neutralWhite,
    hoverForegroundColor: UsPrimitives.neutralWhite,
    pressedForegroundColor: UsPrimitives.neutralWhite,
    textStyle: const TextStyle(
      fontFamily: UsFontFamily.display,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 0,
      color: UsPrimitives.neutralWhite,
    ),
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        color: UsPrimitives.neutral900,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Destructive button theme ────────────────────────────────────────────
  final destructiveButtonTheme = ShadButtonTheme(
    backgroundColor: UsPrimitives.red500,
    hoverBackgroundColor: UsPrimitives.red500,
    pressedBackgroundColor: UsPrimitives.red500,
    foregroundColor: UsPrimitives.neutralWhite,
    hoverForegroundColor: UsPrimitives.neutralWhite,
    pressedForegroundColor: UsPrimitives.neutralWhite,
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        color: UsPrimitives.red500,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Outline button theme — transparent + border ─────────────────────────
  final outlineButtonTheme = ShadButtonTheme(
    backgroundColor: colorScheme.transparent,
    hoverBackgroundColor: UsPrimitives.neutral100,
    pressedBackgroundColor: UsPrimitives.neutral200,
    foregroundColor: UsPrimitives.neutral900,
    hoverForegroundColor: UsPrimitives.neutral900,
    pressedForegroundColor: UsPrimitives.neutral900,
    textStyle: const TextStyle(
      fontFamily: UsFontFamily.display,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 0,
    ),
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 2,
        color: UsPrimitives.neutral400,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Ghost button theme — transparent, no border ─────────────────────────
  final ghostButtonTheme = ShadButtonTheme(
    backgroundColor: colorScheme.transparent,
    hoverBackgroundColor: UsPrimitives.neutral100,
    pressedBackgroundColor: UsPrimitives.neutral200,
    foregroundColor: UsPrimitives.neutral900,
    hoverForegroundColor: UsPrimitives.neutral900,
    pressedForegroundColor: UsPrimitives.neutral900,
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        color: colorScheme.transparent,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Link button theme ───────────────────────────────────────────────────
  final linkButtonTheme = ShadButtonTheme(
    backgroundColor: colorScheme.transparent,
    foregroundColor: UsPrimitives.brown500,
    hoverForegroundColor: UsPrimitives.brown500,
    pressedForegroundColor: UsPrimitives.brown500,
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        color: colorScheme.transparent,
        radius: effectiveRadius,
      ),
    ),
  );

  // ── Input theme ─────────────────────────────────────────────────────────
  final inputTheme = ShadInputTheme(
    cursorColor: UsPrimitives.orange500,
    cursorWidth: 2,
    decoration: ShadDecoration(
      labelStyle: textTheme.custom['labelMd'],
      errorLabelStyle: textTheme.custom['labelMd']?.copyWith(
        color: colorScheme.destructive,
      ),
      border: ShadBorder.all(
        width: 2,
        color: UsPrimitives.neutral400,
        radius: effectiveRadius,
      ),
      focusedBorder: ShadBorder.all(
        width: 2,
        color: UsPrimitives.orange500,
        radius: effectiveRadius,
      ),
      errorBorder: ShadBorder.all(
        width: 2,
        color: UsPrimitives.red500,
        radius: effectiveRadius,
      ),
      errorStyle: const TextStyle(
        fontFamily: UsFontFamily.body,
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w400,
        color: UsPrimitives.red500,
      ),
      shape: BoxShape.rectangle,
    ),
  );

  // ── Dialog theme ────────────────────────────────────────────────────────
  final alertDialogTheme = ShadDialogTheme(
    backgroundColor: UsPrimitives.neutralWhite,
    titleStyle: const TextStyle(
      fontFamily: UsFontFamily.display,
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w700,
      color: UsPrimitives.neutral900,
    ),
    descriptionStyle: const TextStyle(
      fontFamily: UsFontFamily.body,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      color: UsPrimitives.neutral700,
    ),
    border: Border.all(
      width: 2,
      color: UsPrimitives.neutral900,
    ),
    radius: effectiveRadius,
  );

  // ── Card theme ──────────────────────────────────────────────────────────
  final cardTheme = ShadCardTheme(
    border: ShadBorder.all(
      width: 1,
      color: UsPrimitives.neutral400,
    ),
    shadows: UsElevation.sm,
    radius: effectiveRadius,
  );

  // ── Sheet (bottom drawer) theme ─────────────────────────────────────────
  const sheetTheme = ShadSheetTheme(
    backgroundColor: UsPrimitives.neutralWhite,
    constraints: BoxConstraints(maxWidth: 400),
  );

  // ── Badge themes ────────────────────────────────────────────────────────
  const primaryBadgeTheme = ShadBadgeTheme(
    backgroundColor: UsPrimitives.neutral900,
    foregroundColor: UsPrimitives.neutralWhite,
    // textStyle: TextStyle(
    //   fontFamily: UsFontFamily.mono,
    //   fontSize: 10,
    //   height: 14 / 10,
    //   fontWeight: FontWeight.w400,
    //   letterSpacing: 0.5,
    // ),
  );

  const secondaryBadgeTheme = ShadBadgeTheme(
    backgroundColor: UsPrimitives.neutral200,
    foregroundColor: UsPrimitives.neutral700,
    // textStyle: TextStyle(
    //   fontFamily: UsFontFamily.mono,
    //   fontSize: 10,
    //   height: 14 / 10,
    //   fontWeight: FontWeight.w400,
    //   letterSpacing: 0.5,
    // ),
  );

  const destructiveBadgeTheme = ShadBadgeTheme(
    backgroundColor: UsPrimitives.red100,
    foregroundColor: UsPrimitives.red500,
    // textStyle: TextStyle(
    //   fontFamily: UsFontFamily.mono,
    //   fontSize: 10,
    //   height: 14 / 10,
    //   fontWeight: FontWeight.w400,
    //   letterSpacing: 0.5,
    // ),
  );

  // ── Checkbox theme ──────────────────────────────────────────────────────
  final checkboxTheme = ShadCheckboxTheme(
    decoration: ShadDecoration(
      border: ShadBorder.all(
        width: 1.5,
        color: UsPrimitives.neutral400,
        radius: .zero,
      ),
    ),
    color: UsPrimitives.orange500,
    uncheckedColor: UsPrimitives.neutral400,
  );

  // ── Switch theme ────────────────────────────────────────────────────────
  const switchTheme = ShadSwitchTheme(
    thumbColor: UsPrimitives.neutralWhite,
    uncheckedTrackColor: UsPrimitives.neutral400,
    checkedTrackColor: UsPrimitives.orange500,
  );

  // ── Avatar theme ────────────────────────────────────────────────────────
  const avatarTheme = ShadAvatarTheme();

  // ── Progress theme ──────────────────────────────────────────────────────
  const progressTheme = ShadProgressTheme(
    backgroundColor: UsPrimitives.neutral200,
    color: UsPrimitives.orange500,
  );

  // ── Separator theme ─────────────────────────────────────────────────────
  const separatorTheme = ShadSeparatorTheme(
    thickness: 1,
    color: UsPrimitives.neutral400,
  );

  // ── Tooltip theme ───────────────────────────────────────────────────────
  final tooltipTheme = ShadTooltipTheme(
    decoration: ShadDecoration(
      color: UsPrimitives.neutral900,
      border: ShadBorder.all(
        width: 1.5,
        color: UsPrimitives.neutral400,
        radius: .zero,
      ),
      shadows: UsElevation.sm,
      labelStyle: const TextStyle(
        fontFamily: UsFontFamily.body,
        fontSize: 12,
        height: 18 / 12,
        color: UsPrimitives.neutralWhite,
      ),
    ),
  );

  final destructiveToastTheme = ShadToastTheme(
    alignment: .bottomCenter,
    backgroundColor: UsPrimitives.red500,
    border: ShadBorder.all(
      width: 2,
      color: UsPrimitives.neutral900,
      radius: .zero,
    ),
    shadows: UsElevation.brutalist,
  );

  // ── Assemble ShadThemeData ──────────────────────────────────────────────
  return ShadThemeData(
    colorScheme: colorScheme,
    brightness: Brightness.light,
    radius: effectiveRadius,
    textTheme: textTheme,
    disableSecondaryBorder: true,

    // Button themes
    primaryButtonTheme: primaryButtonTheme,
    secondaryButtonTheme: secondaryButtonTheme,
    destructiveButtonTheme: destructiveButtonTheme,
    outlineButtonTheme: outlineButtonTheme,
    ghostButtonTheme: ghostButtonTheme,
    linkButtonTheme: linkButtonTheme,

    // Badge themes
    primaryBadgeTheme: primaryBadgeTheme,
    secondaryBadgeTheme: secondaryBadgeTheme,
    destructiveBadgeTheme: destructiveBadgeTheme,

    // Input / Form
    inputTheme: inputTheme,
    checkboxTheme: checkboxTheme,
    switchTheme: switchTheme,

    // Overlay surfaces
    cardTheme: cardTheme,
    alertDialogTheme: alertDialogTheme,
    sheetTheme: sheetTheme,
    tooltipTheme: tooltipTheme,

    // Misc
    avatarTheme: avatarTheme,
    progressTheme: progressTheme,
    separatorTheme: separatorTheme,
    destructiveToastTheme: destructiveToastTheme,
  );
}
