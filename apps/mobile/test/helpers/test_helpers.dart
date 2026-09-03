import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';

/// Wraps [child] in [MaterialApp] + [ShadTheme] with the UniStash color scheme.
Widget buildTestApp({required Widget child}) {
  return MaterialApp(
    home: ShadTheme(
      data: ShadThemeData(
        colorScheme: UniStashColorScheme.light(),
      ),
      child: child,
    ),
  );
}
