import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/_router.dart';
import 'package:uni_stash_mobile/core/signals/signal_listenable.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/listings/pages/home_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter routerConfig = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: UsRoutes.home,
  refreshListenable: SignalListenable(di<AuthViewModel>().status),
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
