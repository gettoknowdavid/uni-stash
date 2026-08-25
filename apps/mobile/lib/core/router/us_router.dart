import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/auth/auth_status.dart';
import 'package:uni_stash_mobile/core/router/_router.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/listings/pages/home_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter routerConfig = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: UsRoutes.home,
  refreshListenable: authStatus as ValueListenable<AuthStatus>,
  redirect: usRedirect,
  routes: [
    GoRoute(
      path: UsRoutes.login,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: UsRoutes.home,
      builder: (context, state) => const HomePage(),
    ),
  ],
);
