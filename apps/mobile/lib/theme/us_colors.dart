import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Raw hex color primitives from the UniStash design system.
abstract final class UsPrimitives {
  const UsPrimitives._();

  static const Color neutralWhite = Color(0xFFFFFFFF);
  static const Color neutralBlack = Color(0xFF000000);
  static const Color neutral50 = Color(0xFFFAF9F5);
  static const Color neutral100 = Color(0xFFF7F6F2);
  static const Color neutral200 = Color(0xFFEFEEEA);
  static const Color neutral300 = Color(0xFFE9E8E4);
  static const Color neutral400 = Color(0xFFE3E2DF);
  static const Color neutral500 = Color(0xFFD8DAD6);
  static const Color neutral600 = Color(0xFF8F7067);
  static const Color neutral700 = Color(0xFF6B7280);
  static const Color neutral800 = Color(0xFF5B4138);
  static const Color neutral900 = Color(0xFF15140F);

  static const Color orange100 = Color(0xFFFFB59D);
  static const Color orange200 = Color(0xFFD17A5D);
  static const Color orange500 = Color(0xFFFF5B1F);

  static const Color brown100 = Color(0xFFE4BEB3);
  static const Color brown300 = Color(0xFF8F7067);
  static const Color brown500 = Color(0xFF5B4138);

  static const Color sage100 = Color(0xFFD7E8C8);
  static const Color sage300 = Color(0xFF8A9A7E);
  static const Color sage500 = Color(0xFF5A6950);

  static const Color red100 = Color(0xFFFFDAD6);
  static const Color red500 = Color(0xFFBA1A1A);

  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue500 = Color(0xFF2563EB);

  static const Color transparent = Color(0x00000000);
}

/// UniStash light color scheme mapped to Shadcn's color roles.
///
/// Usage:
/// ```dart
/// ShadThemeData(
///   colorScheme: const UniStashColorScheme.light(),
/// )
/// ```
class UniStashColorScheme extends ShadColorScheme {
  UniStashColorScheme.light()
    : super(
        background: UsPrimitives.neutral50,
        foreground: UsPrimitives.neutral900,
        card: UsPrimitives.neutralWhite,
        cardForeground: UsPrimitives.neutral900,
        popover: UsPrimitives.neutral50,
        popoverForeground: UsPrimitives.neutral900,
        primary: UsPrimitives.orange500,
        primaryForeground: UsPrimitives.neutralWhite,
        secondary: UsPrimitives.neutral100,
        secondaryForeground: UsPrimitives.neutral900,
        muted: UsPrimitives.neutral200,
        mutedForeground: UsPrimitives.neutral700,
        accent: UsPrimitives.neutral100,
        accentForeground: UsPrimitives.neutral900,
        destructive: UsPrimitives.red500,
        destructiveForeground: UsPrimitives.neutralWhite,
        border: UsPrimitives.neutral400,
        input: UsPrimitives.neutral400,
        ring: UsPrimitives.orange500,
        selection: UsPrimitives.orange500,
        custom: {
          'transparent': UsPrimitives.transparent,
          'textSecondary': UsPrimitives.brown300,
          'textTertiary': UsPrimitives.neutral700,
          'textLink': UsPrimitives.blue500,
          'textDisabled': UsPrimitives.neutral500,
          'textOnPrimary': UsPrimitives.neutralWhite,
          'textOnSecondary': UsPrimitives.neutralWhite,
          'borderSubtle': UsPrimitives.neutral200,
          'borderStrong': UsPrimitives.neutral900,
          'borderFocus': UsPrimitives.orange500,
          'surfaceInput': UsPrimitives.neutralWhite,
          'surfaceOverlay': UsPrimitives.neutral50,
          'surfaceDisabled': UsPrimitives.neutral200,
          'surfaceAccent': UsPrimitives.orange100,
          'surfaceAccentSubtle': UsPrimitives.neutral100,
          'actionPrimaryHover': UsPrimitives.orange200,
          'actionPrimaryPressed': UsPrimitives.brown500,
          'actionSecondary': UsPrimitives.neutral900,
          'actionSecondaryHover': UsPrimitives.neutral800,
          'actionDisabled': UsPrimitives.neutral400,
          'statusSuccess': UsPrimitives.sage300,
          'statusSuccessBg': UsPrimitives.sage100,
          'statusError': UsPrimitives.red500,
          'statusErrorBg': UsPrimitives.red100,
          'statusWarning': UsPrimitives.orange500,
          'statusWarningBg': UsPrimitives.orange100,
          'statusInfo': UsPrimitives.blue500,
          'statusInfoBg': UsPrimitives.blue100,
          'iconPrimary': UsPrimitives.neutral900,
          'iconSecondary': UsPrimitives.brown300,
          'iconAccent': UsPrimitives.orange500,
          'iconDisabled': UsPrimitives.neutral500,
        },
      );
}

extension CustomColorExtension on ShadColorScheme {
  Color get transparent => custom['transparent']!;
  Color get textSecondary => custom['textSecondary']!;
  Color get textTertiary => custom['textTertiary']!;
  Color get textLink => custom['textLink']!;
  Color get textDisabled => custom['textDisabled']!;
  Color get textOnPrimary => custom['textOnPrimary']!;
  Color get textOnSecondary => custom['textOnSecondary']!;
  Color get borderSubtle => custom['borderSubtle']!;
  Color get borderStrong => custom['borderStrong']!;
  Color get borderFocus => custom['borderFocus']!;
  Color get surfaceInput => custom['surfaceInput']!;
  Color get surfaceOverlay => custom['surfaceOverlay']!;
  Color get surfaceDisabled => custom['surfaceDisabled']!;
  Color get surfaceAccent => custom['surfaceAccent']!;
  Color get surfaceAccentSubtle => custom['surfaceAccentSubtle']!;
  Color get actionPrimaryHover => custom['actionPrimaryHover']!;
  Color get actionPrimaryPressed => custom['actionPrimaryPressed']!;
  Color get actionSecondary => custom['actionSecondary']!;
  Color get actionSecondaryHover => custom['actionSecondaryHover']!;
  Color get actionDisabled => custom['actionDisabled']!;
  Color get statusSuccess => custom['statusSuccess']!;
  Color get statusSuccessBg => custom['statusSuccessBg']!;
  Color get statusError => custom['statusError']!;
  Color get statusErrorBg => custom['statusErrorBg']!;
  Color get statusWarning => custom['statusWarning']!;
  Color get statusWarningBg => custom['statusWarningBg']!;
  Color get statusInfo => custom['statusInfo']!;
  Color get statusInfoBg => custom['statusInfoBg']!;
  Color get iconPrimary => custom['iconPrimary']!;
  Color get iconSecondary => custom['iconSecondary']!;
  Color get iconAccent => custom['iconAccent']!;
  Color get iconDisabled => custom['iconDisabled']!;
}
