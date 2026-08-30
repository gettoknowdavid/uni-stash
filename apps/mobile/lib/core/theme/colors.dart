import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// UniStash light color scheme.
///
/// Maps the Figma design-system tokens onto Forui's [FColors] fields.
/// Extra semantic tokens live in [UsColors] and are accessed via
/// `context.theme.colors.us`.
final FColors usLightColors = FColors(
  brightness: .light,
  systemOverlayStyle: .dark,
  barrier: const Color(0x33000000),

  // bg/primary
  background: const Color(0xFFFFFFFF),

  // text/primary
  foreground: const Color(0xFF15140F),

  // action/primary
  primary: const Color(0xFFFF5B1F),

  // text/inverse
  primaryForeground: const Color(0xFFFFFFFF),

  // bg/secondary
  secondary: const Color(0xFFFAF9F5),

  // text/primary
  secondaryForeground: const Color(0xFF15140F),

  // bg/tertiary
  muted: const Color(0xFFF7F6F2),

  // text/tertiary
  mutedForeground: const Color(0xFF6B7280),

  // status/error
  destructive: const Color(0xFFBA1A1A),

  // text/inverse
  destructiveForeground: const Color(0xFFFFFFFF),

  // status/error
  error: const Color(0xFFBA1A1A),

  // text/inverse
  errorForeground: const Color(0xFFFFFFFF),

  // surface/card
  card: const Color(0xFFFFFFFF),

  // border/default
  border: const Color(0xFF000000),

  extensions: [const UsColors()],
);

// ---------------------------------------------------------------------------
// UsColors — extra semantic tokens not covered by FColors.
// ---------------------------------------------------------------------------

/// Provides convenient access via `context.theme.colors.us`.
extension UsColorsExtension on FColors {
  UsColors get us => extension<UsColors>();
}

/// Additional color tokens specific to the UniStash design system.
///
/// Access through [UsColorsExtension]:
/// ```dart
/// final linkColor = context.theme.colors.us.textLink;
/// ```
@immutable
class UsColors extends ThemeExtension<UsColors> {
  const UsColors({
    this.textSecondary = const Color(0xFF8F7067),
    this.textLink = const Color(0xFF2563EB),
    this.borderSubtle = const Color(0xFFEFEEEA),
    this.borderStrong = const Color(0xFF15140F),
    this.surfaceInput = const Color(0xFFFFFFFF),
    this.surfaceOverlay = const Color(0xFFFAF9F5),
    this.actionPrimaryHover = const Color(0xFFD17A5D),
    this.actionSecondary = const Color(0xFF15140F),
    this.statusSuccess = const Color(0xFF8A9A7E),
    this.statusSuccessBg = const Color(0xFFD7E8C8),
    this.statusErrorBg = const Color(0xFFFFDAD6),
    this.statusWarning = const Color(0xFFFF5B1F),
    this.statusWarningBg = const Color(0xFFFFB59D),
    this.statusInfo = const Color(0xFF2563EB),
    this.iconPrimary = const Color(0xFF15140F),
    this.iconSecondary = const Color(0xFF8F7067),
    this.iconAccent = const Color(0xFFFF5B1F),
  });

  final Color textSecondary;
  final Color textLink;

  final Color borderSubtle;
  final Color borderStrong;

  final Color surfaceInput;
  final Color surfaceOverlay;

  final Color actionPrimaryHover;
  final Color actionSecondary;

  final Color statusSuccess;
  final Color statusSuccessBg;
  final Color statusErrorBg;
  final Color statusWarning;
  final Color statusWarningBg;
  final Color statusInfo;

  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconAccent;

  @override
  UsColors copyWith({
    Color? textSecondary,
    Color? textLink,
    Color? borderSubtle,
    Color? borderStrong,
    Color? surfaceInput,
    Color? surfaceOverlay,
    Color? actionPrimaryHover,
    Color? actionSecondary,
    Color? statusSuccess,
    Color? statusSuccessBg,
    Color? statusErrorBg,
    Color? statusWarning,
    Color? statusWarningBg,
    Color? statusInfo,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconAccent,
  }) {
    return UsColors(
      textSecondary: textSecondary ?? this.textSecondary,
      textLink: textLink ?? this.textLink,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      actionPrimaryHover: actionPrimaryHover ?? this.actionPrimaryHover,
      actionSecondary: actionSecondary ?? this.actionSecondary,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusSuccessBg: statusSuccessBg ?? this.statusSuccessBg,
      statusErrorBg: statusErrorBg ?? this.statusErrorBg,
      statusWarning: statusWarning ?? this.statusWarning,
      statusWarningBg: statusWarningBg ?? this.statusWarningBg,
      statusInfo: statusInfo ?? this.statusInfo,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconAccent: iconAccent ?? this.iconAccent,
    );
  }

  @override
  UsColors lerp(covariant UsColors? other, double t) {
    if (other is! UsColors) return this;
    return UsColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      surfaceInput: Color.lerp(surfaceInput, other.surfaceInput, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      actionPrimaryHover: Color.lerp(
        actionPrimaryHover,
        other.actionPrimaryHover,
        t,
      )!,
      actionSecondary: Color.lerp(actionSecondary, other.actionSecondary, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusSuccessBg: Color.lerp(statusSuccessBg, other.statusSuccessBg, t)!,
      statusErrorBg: Color.lerp(statusErrorBg, other.statusErrorBg, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusWarningBg: Color.lerp(statusWarningBg, other.statusWarningBg, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconAccent: Color.lerp(iconAccent, other.iconAccent, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsColors &&
          runtimeType == other.runtimeType &&
          textSecondary == other.textSecondary &&
          textLink == other.textLink &&
          borderSubtle == other.borderSubtle &&
          borderStrong == other.borderStrong &&
          surfaceInput == other.surfaceInput &&
          surfaceOverlay == other.surfaceOverlay &&
          actionPrimaryHover == other.actionPrimaryHover &&
          actionSecondary == other.actionSecondary &&
          statusSuccess == other.statusSuccess &&
          statusSuccessBg == other.statusSuccessBg &&
          statusErrorBg == other.statusErrorBg &&
          statusWarning == other.statusWarning &&
          statusWarningBg == other.statusWarningBg &&
          statusInfo == other.statusInfo &&
          iconPrimary == other.iconPrimary &&
          iconSecondary == other.iconSecondary &&
          iconAccent == other.iconAccent;

  @override
  int get hashCode => Object.hash(
    textSecondary,
    textLink,
    borderSubtle,
    borderStrong,
    surfaceInput,
    surfaceOverlay,
    actionPrimaryHover,
    actionSecondary,
    statusSuccess,
    statusSuccessBg,
    statusErrorBg,
    statusWarning,
    statusWarningBg,
    statusInfo,
    iconPrimary,
    iconSecondary,
    iconAccent,
  );
}
