import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/signals/signal_listenable.dart';
import 'package:uni_stash_mobile/features/auth/pages/_pages.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/chats/pages/_pages.dart';
import 'package:uni_stash_mobile/features/listings/pages/_pages.dart';
import 'package:uni_stash_mobile/features/profile/pages/_pages.dart';
import 'package:uni_stash_mobile/features/schools/pages/_pages.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _homeNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _searchNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _sellNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _chatNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _profileNavKey = GlobalKey<NavigatorState>();

final GoRouter routerConfig = GoRouter(
  navigatorKey: _rootNavKey,
  initialLocation: UsRoutes.home,
  // Listen to status *and* verification state so redirects re-run when a
  // session verifies its email (e.g. OTP success) as well as on sign-in/out.
  refreshListenable: SignalListenable(di<AuthViewModel>().routerRefresh),
  redirect: usRedirect,
  errorBuilder: (context, state) => const NotFoundPage(),
  routes: [
    GoRoute(
      path: UsRoutes.login,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: UsRoutes.signup,
      builder: (context, state) => const SignUpPage(),
    ),
    GoRoute(
      path: UsRoutes.forgotPw,
      builder: (context, state) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: UsRoutes.resetPw,
      builder: (context, state) => ResetPasswordPage(
        email: state.uri.queryParameters['email'],
      ),
    ),
    GoRoute(
      path: UsRoutes.verify,
      builder: (context, state) => VerifyPage(
        email: state.uri.queryParameters['email'],
        code: state.uri.queryParameters['code'],
      ),
    ),
    GoRoute(
      path: UsRoutes.schools,
      builder: (context, state) => const SchoolsPage(),
    ),
    GoRoute(
      path: UsRoutes.listingEditor,
      builder: (context, state) => const ListingEditor(),
      pageBuilder: (context, state) {
        return CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 310),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final slideTween = Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic));

            final fadeTween = CurveTween(curve: Curves.easeInOut);

            return FadeTransition(
              opacity: animation.drive(fadeTween),
              child: SlideTransition(
                position: animation.drive(slideTween),
                child: child,
              ),
            );
          },
          child: const ListingEditor(),
        );
      },
    ),
    GoRoute(
      path: UsRoutes.listingDetails,
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ListingDetailPage(id: id);
      },
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => MainShell(
        navigationShell: navigationShell,
      ),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavKey,
          routes: [
            GoRoute(
              path: UsRoutes.home,
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _searchNavKey,
          routes: [
            GoRoute(
              path: UsRoutes.search,
              builder: (context, state) => const SearchPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _sellNavKey,
          routes: [
            GoRoute(
              path: UsRoutes.sell,
              builder: (context, state) => const SellPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _chatNavKey,
          routes: [
            GoRoute(
              path: UsRoutes.chat,
              builder: (context, state) => const ChatPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _profileNavKey,
          routes: [
            GoRoute(
              path: UsRoutes.profile,
              builder: (context, state) => const ProfilePage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
