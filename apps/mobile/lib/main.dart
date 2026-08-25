import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/us_router.dart';
import 'package:uni_stash_mobile/core/theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register all dependencies (Logger, Dio, ApiClient, etc.)
  configureDependencies();

  // Wait for async singletons (Dio reads secure storage, etc.)
  await GetIt.I.allReady();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = usLightTheme;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'UniStash',
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      routerConfig: routerConfig,
    );
  }
}
