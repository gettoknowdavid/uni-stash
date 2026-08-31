import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/us_router.dart';
import 'package:uni_stash_mobile/core/theme/theme.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

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
    return ShadApp.router(
      title: 'UniStash',
      theme: usLightTheme,
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
  }
}
