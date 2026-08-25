import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/auth/_auth.dart';
import 'package:uni_stash_mobile/core/router/us_routes.dart';

String? usRedirect(BuildContext context, GoRouterState state) {
  final status = authStatus.value;
  final isAuthRoute = [
    UsRoutes.login,
    UsRoutes.signup,
    UsRoutes.verify,
  ].contains(state.matchedLocation);

  if (status == .loading) return null;
  if (status == .unauthenticated && !isAuthRoute) return UsRoutes.login;
  if (status == .authenticated && isAuthRoute) return UsRoutes.home;

  return null;
}
