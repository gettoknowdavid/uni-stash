import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// Color Primitives
// ---------------------------------------------------------------------------

/// Raw hex color primitives from the UniStash design system.
abstract final class UsPrimitives {
  const UsPrimitives._();

  // ── Neutrals ──────────────────────────────────────────────────────────────
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

  // ── Orange ────────────────────────────────────────────────────────────────
  static const Color orange100 = Color(0xFFFFB59D);
  static const Color orange200 = Color(0xFFD17A5D);
  static const Color orange500 = Color(0xFFFF5B1F);

  // ── Brown ─────────────────────────────────────────────────────────────────
  static const Color brown100 = Color(0xFFE4BEB3);
  static const Color brown300 = Color(0xFF8F7067);
  static const Color brown500 = Color(0xFF5B4138);

  // ── Sage ──────────────────────────────────────────────────────────────────
  static const Color sage100 = Color(0xFFD7E8C8);
  static const Color sage300 = Color(0xFF8A9A7E);
  static const Color sage500 = Color(0xFF5A6950);

  // ── Red ───────────────────────────────────────────────────────────────────
  static const Color red100 = Color(0xFFFFDAD6);
  static const Color red500 = Color(0xFFBA1A1A);

  // ── Blue ──────────────────────────────────────────────────────────────────
  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue500 = Color(0xFF2563EB);
}

// ---------------------------------------------------------------------------
// FColors — UniStash light theme
// ---------------------------------------------------------------------------

/// UniStash light color scheme.
///
/// Maps the design-system tokens onto Forui's [FColors] fields.
/// Extra semantic tokens live in [UsColors] and are accessed via
/// `context.theme.colors.us`.
final FColors usLightColors = FColors(
  brightness: .light,
  systemOverlayStyle: .dark,
  barrier: const Color(0x33000000),

  // ── Backgrounds ───────────────────────────────────────────────────────────
  // bg/primary → white
  background: UsPrimitives.neutral50, // #FAF9F5 — default page bg
  // text/primary
  foreground: UsPrimitives.neutral900, // #15140F

  // ── Primary (action/primary) ──────────────────────────────────────────────
  primary: UsPrimitives.orange500, // #FF5B1F
  primaryForeground: UsPrimitives.neutralWhite, // #FFFFFF

  // ── Secondary (bg/secondary) ──────────────────────────────────────────────
  secondary: UsPrimitives.neutral50, // #FAF9F5
  secondaryForeground: UsPrimitives.neutral900, // #15140F

  // ── Muted (bg/tertiary) ──────────────────────────────────────────────────
  muted: UsPrimitives.neutral100, // #F7F6F2
  mutedForeground: UsPrimitives.neutral700, // #6B7280

  // ── Destructive / Error ──────────────────────────────────────────────────
  destructive: UsPrimitives.red500, // #BA1A1A
  destructiveForeground: UsPrimitives.neutralWhite, // #FFFFFF
  error: UsPrimitives.red500, // #BA1A1A
  errorForeground: UsPrimitives.neutralWhite, // #FFFFFF

  // ── Surfaces ─────────────────────────────────────────────────────────────
  card: UsPrimitives.neutralWhite, // #FFFFFF

  // ── Borders ──────────────────────────────────────────────────────────────
  // border/default — subtle for inputs, cards
  border: UsPrimitives.neutral400, // #E3E2DF

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
    // ── Text Roles ────────────────────────────────────────────────────────
    this.textSecondary = UsPrimitives.brown300,
    this.textTertiary = UsPrimitives.neutral700,
    this.textLink = UsPrimitives.blue500,
    this.textDisabled = UsPrimitives.neutral500,
    this.textOnPrimary = UsPrimitives.neutralWhite,
    this.textOnSecondary = UsPrimitives.neutralWhite,

    // ── Borders ────────────────────────────────────────────────────────────
    this.borderSubtle = UsPrimitives.neutral200,
    this.borderStrong = UsPrimitives.neutral900,
    this.borderFocus = UsPrimitives.orange500,

    // ── Surfaces ───────────────────────────────────────────────────────────
    this.surfaceInput = UsPrimitives.neutralWhite,
    this.surfaceOverlay = UsPrimitives.neutral50,
    this.surfaceDisabled = UsPrimitives.neutral200,
    this.surfaceAccent = UsPrimitives.orange100,
    this.surfaceAccentSubtle = UsPrimitives.neutral100,

    // ── Actions ────────────────────────────────────────────────────────────
    this.actionPrimaryHover = UsPrimitives.orange200,
    this.actionPrimaryPressed = UsPrimitives.brown500,
    this.actionSecondary = UsPrimitives.neutral900,
    this.actionSecondaryHover = UsPrimitives.neutral800,
    this.actionDisabled = UsPrimitives.neutral400,

    // ── Status Feedback ────────────────────────────────────────────────────
    this.statusSuccess = UsPrimitives.sage300,
    this.statusSuccessBg = UsPrimitives.sage100,
    this.statusError = UsPrimitives.red500,
    this.statusErrorBg = UsPrimitives.red100,
    this.statusWarning = UsPrimitives.orange500,
    this.statusWarningBg = UsPrimitives.orange100,
    this.statusInfo = UsPrimitives.blue500,
    this.statusInfoBg = UsPrimitives.blue100,

    // ── Icons ──────────────────────────────────────────────────────────────
    this.iconPrimary = UsPrimitives.neutral900,
    this.iconSecondary = UsPrimitives.brown300,
    this.iconAccent = UsPrimitives.orange500,
    this.iconDisabled = UsPrimitives.neutral500,
  });

  // ── Text Roles ──────────────────────────────────────────────────────────
  final Color textSecondary;
  final Color textTertiary;
  final Color textLink;
  final Color textDisabled;
  final Color textOnPrimary;
  final Color textOnSecondary;

  // ── Borders ──────────────────────────────────────────────────────────────
  final Color borderSubtle;
  final Color borderStrong;
  final Color borderFocus;

  // ── Surfaces ─────────────────────────────────────────────────────────────
  final Color surfaceInput;
  final Color surfaceOverlay;
  final Color surfaceDisabled;
  final Color surfaceAccent;
  final Color surfaceAccentSubtle;

  // ── Actions ──────────────────────────────────────────────────────────────
  final Color actionPrimaryHover;
  final Color actionPrimaryPressed;
  final Color actionSecondary;
  final Color actionSecondaryHover;
  final Color actionDisabled;

  // ── Status Feedback ──────────────────────────────────────────────────────
  final Color statusSuccess;
  final Color statusSuccessBg;
  final Color statusError;
  final Color statusErrorBg;
  final Color statusWarning;
  final Color statusWarningBg;
  final Color statusInfo;
  final Color statusInfoBg;

  // ── Icons ────────────────────────────────────────────────────────────────
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconAccent;
  final Color iconDisabled;

  @override
  UsColors copyWith({
    Color? textSecondary,
    Color? textTertiary,
    Color? textLink,
    Color? textDisabled,
    Color? textOnPrimary,
    Color? textOnSecondary,
    Color? borderSubtle,
    Color? borderStrong,
    Color? borderFocus,
    Color? surfaceInput,
    Color? surfaceOverlay,
    Color? surfaceDisabled,
    Color? surfaceAccent,
    Color? surfaceAccentSubtle,
    Color? actionPrimaryHover,
    Color? actionPrimaryPressed,
    Color? actionSecondary,
    Color? actionSecondaryHover,
    Color? actionDisabled,
    Color? statusSuccess,
    Color? statusSuccessBg,
    Color? statusError,
    Color? statusErrorBg,
    Color? statusWarning,
    Color? statusWarningBg,
    Color? statusInfo,
    Color? statusInfoBg,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconAccent,
    Color? iconDisabled,
  }) {
    return UsColors(
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textLink: textLink ?? this.textLink,
      textDisabled: textDisabled ?? this.textDisabled,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      textOnSecondary: textOnSecondary ?? this.textOnSecondary,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      surfaceDisabled: surfaceDisabled ?? this.surfaceDisabled,
      surfaceAccent: surfaceAccent ?? this.surfaceAccent,
      surfaceAccentSubtle: surfaceAccentSubtle ?? this.surfaceAccentSubtle,
      actionPrimaryHover: actionPrimaryHover ?? this.actionPrimaryHover,
      actionPrimaryPressed: actionPrimaryPressed ?? this.actionPrimaryPressed,
      actionSecondary: actionSecondary ?? this.actionSecondary,
      actionSecondaryHover: actionSecondaryHover ?? this.actionSecondaryHover,
      actionDisabled: actionDisabled ?? this.actionDisabled,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusSuccessBg: statusSuccessBg ?? this.statusSuccessBg,
      statusError: statusError ?? this.statusError,
      statusErrorBg: statusErrorBg ?? this.statusErrorBg,
      statusWarning: statusWarning ?? this.statusWarning,
      statusWarningBg: statusWarningBg ?? this.statusWarningBg,
      statusInfo: statusInfo ?? this.statusInfo,
      statusInfoBg: statusInfoBg ?? this.statusInfoBg,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconAccent: iconAccent ?? this.iconAccent,
      iconDisabled: iconDisabled ?? this.iconDisabled,
    );
  }

  @override
  UsColors lerp(covariant UsColors? other, double t) {
    if (other is! UsColors) return this;
    return UsColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      textOnSecondary: Color.lerp(textOnSecondary, other.textOnSecondary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      surfaceInput: Color.lerp(surfaceInput, other.surfaceInput, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceDisabled: Color.lerp(surfaceDisabled, other.surfaceDisabled, t)!,
      surfaceAccent: Color.lerp(surfaceAccent, other.surfaceAccent, t)!,
      surfaceAccentSubtle: Color.lerp(
        surfaceAccentSubtle,
        other.surfaceAccentSubtle,
        t,
      )!,
      actionPrimaryHover: Color.lerp(
        actionPrimaryHover,
        other.actionPrimaryHover,
        t,
      )!,
      actionPrimaryPressed: Color.lerp(
        actionPrimaryPressed,
        other.actionPrimaryPressed,
        t,
      )!,
      actionSecondary: Color.lerp(actionSecondary, other.actionSecondary, t)!,
      actionSecondaryHover: Color.lerp(
        actionSecondaryHover,
        other.actionSecondaryHover,
        t,
      )!,
      actionDisabled: Color.lerp(actionDisabled, other.actionDisabled, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusSuccessBg: Color.lerp(statusSuccessBg, other.statusSuccessBg, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusErrorBg: Color.lerp(statusErrorBg, other.statusErrorBg, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusWarningBg: Color.lerp(statusWarningBg, other.statusWarningBg, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusInfoBg: Color.lerp(statusInfoBg, other.statusInfoBg, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconAccent: Color.lerp(iconAccent, other.iconAccent, t)!,
      iconDisabled: Color.lerp(iconDisabled, other.iconDisabled, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsColors &&
          runtimeType == other.runtimeType &&
          textSecondary == other.textSecondary &&
          textTertiary == other.textTertiary &&
          textLink == other.textLink &&
          textDisabled == other.textDisabled &&
          textOnPrimary == other.textOnPrimary &&
          textOnSecondary == other.textOnSecondary &&
          borderSubtle == other.borderSubtle &&
          borderStrong == other.borderStrong &&
          borderFocus == other.borderFocus &&
          surfaceInput == other.surfaceInput &&
          surfaceOverlay == other.surfaceOverlay &&
          surfaceDisabled == other.surfaceDisabled &&
          surfaceAccent == other.surfaceAccent &&
          surfaceAccentSubtle == other.surfaceAccentSubtle &&
          actionPrimaryHover == other.actionPrimaryHover &&
          actionPrimaryPressed == other.actionPrimaryPressed &&
          actionSecondary == other.actionSecondary &&
          actionSecondaryHover == other.actionSecondaryHover &&
          actionDisabled == other.actionDisabled &&
          statusSuccess == other.statusSuccess &&
          statusSuccessBg == other.statusSuccessBg &&
          statusError == other.statusError &&
          statusErrorBg == other.statusErrorBg &&
          statusWarning == other.statusWarning &&
          statusWarningBg == other.statusWarningBg &&
          statusInfo == other.statusInfo &&
          statusInfoBg == other.statusInfoBg &&
          iconPrimary == other.iconPrimary &&
          iconSecondary == other.iconSecondary &&
          iconAccent == other.iconAccent &&
          iconDisabled == other.iconDisabled;

  @override
  int get hashCode => Object.hash(
        Object.hash(
          textSecondary,
          textTertiary,
          textLink,
          textDisabled,
          textOnPrimary,
          textOnSecondary,
          borderSubtle,
          borderStrong,
          borderFocus,
          surfaceInput,
          surfaceOverlay,
          surfaceDisabled,
          surfaceAccent,
          surfaceAccentSubtle,
          actionPrimaryHover,
          actionPrimaryPressed,
          actionSecondary,
          actionSecondaryHover,
          actionDisabled,
          statusSuccess,
        ),
        Object.hash(
          statusSuccessBg,
          statusError,
          statusErrorBg,
          statusWarning,
          statusWarningBg,
          statusInfo,
          statusInfoBg,
          iconPrimary,
          iconSecondary,
          iconAccent,
          iconDisabled,
        ),
      );
}
