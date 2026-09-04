import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Wraps [child] in [MaterialApp] + [ShadTheme] with the production UniStash
/// theme, mirroring the real shell: the toaster sits above the navigator so
/// pages can show toasts via [ShadToaster.of].
Widget buildTestApp({required Widget child}) {
  return ShadTheme(
    data: usLightTheme,
    child: MaterialApp(
      home: child,
      builder: (context, child) => ShadToaster(child: child!),
    ),
  );
}
