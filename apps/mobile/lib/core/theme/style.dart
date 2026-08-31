// ---------------------------------------------------------------------------
// Spacing tokens (Base-4)
// ---------------------------------------------------------------------------

import 'package:flutter/widgets.dart';

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

/// Corner radius tokens.
///
/// The global border radius is capped at `sm` (4px) per the project
/// requirement. Larger values are used only in specific overrides.
abstract final class UsRadius {
  const UsRadius._();

  /// Hard corners (0px) — checkboxes, square icons
  static const double none = 0;

  /// **Global max** — buttons, input fields, subtle panels (4px)
  static const double sm = 4;

  /// Badges, minor cards (8px) — used sparingly
  static const double md = 8;

  /// Grid items, main listing cards (12px) — used sparingly
  static const double lg = 12;

  /// Large modal containers (16px) — used sparingly
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
