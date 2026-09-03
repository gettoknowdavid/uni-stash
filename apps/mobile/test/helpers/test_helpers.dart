import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/us_colors.dart';

/// Wraps [child] in [MaterialApp] + [ShadTheme] with the UniStash color scheme,
/// mirroring the production shell: the toaster sits above the navigator so
/// pages can show toasts via [ShadToaster.of].
Widget buildTestApp({required Widget child}) {
  return ShadTheme(
    data: ShadThemeData(
      colorScheme: UniStashColorScheme.light(),
    ),
    child: MaterialApp(
      home: child,
      builder: (context, child) => ShadToaster(child: child!),
    ),
  );
}
