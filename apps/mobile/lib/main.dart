import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/router/us_router.dart';
import 'package:uni_stash_mobile/shared/widgets/back_button.dart';
import 'package:uni_stash_mobile/theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  await GetIt.I.allReady();
  await GetIt.I<AuthViewModel>().bootstrap();
  runApp(const UniStashApp());
}

class UniStashApp extends StatelessWidget {
  const UniStashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      theme: usLightTheme,
      appBuilder: (context) {
        final theme = Theme.of(context).copyWith(
          appBarTheme: const AppBarTheme(leadingWidth: 72),
          actionIconTheme: ActionIconThemeData(
            backButtonIconBuilder: (_) => const UsBackButton(),
          ),
        );

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'UniStash',
          theme: theme,
          localizationsDelegates: const [
            GlobalShadLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          builder: (context, child) => child!,
          routerConfig: routerConfig,
        );
      },
    );
  }
}
