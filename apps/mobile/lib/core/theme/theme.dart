import 'package:forui/forui.dart';

import 'package:uni_stash_mobile/core/theme/colors.dart';
import 'package:uni_stash_mobile/core/theme/style.dart';
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

  final colors = usLightColors;
  final typography = usTypography(colors: colors, touch: touch);
  final style = usStyle(
    colors: colors,
    typography: typography,
    touch: touch,
  );

  return FThemeData(
      colors: colors,
      typography: typography,
      icons: const FIcons.lucide(),
      style: style,
      touch: touch,
  );
}
