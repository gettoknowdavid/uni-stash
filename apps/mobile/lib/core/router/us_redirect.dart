import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/router/us_routes.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

String? usRedirect(BuildContext context, GoRouterState state) {
  final status = di<AuthViewModel>().status.value;
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
