import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/router/_router.dart';

/// Routes that don't require an authenticated session. [UsRoutes.verify] is
/// intentionally here: the OTP flow must also be reachable from a rejected
/// login (account exists but email not verified), where no session exists yet.
const List<String> _authRoutes = [
  UsRoutes.login,
  UsRoutes.signup,
  UsRoutes.verify,
  UsRoutes.forgotPw,
  UsRoutes.resetPw,
];

String? usRedirect(BuildContext context, GoRouterState state) {
  final auth = di<AuthViewModel>();
  final status = auth.status.value;
  final location = state.matchedLocation;
  final isAuthRoute = _authRoutes.contains(location);

  if (status == .loading) return null;

  // Signed out: only the auth routes stay reachable.
  if (status == .unauthenticated) {
    return isAuthRoute ? null : UsRoutes.login;
  }

  // Signed in but the email is not verified: force the OTP verification
  // flow. This covers the signup path and app restarts with a stored session
  // whose account never finished verifying — the user is authenticated yet
  // must land on /verify, not the shell.
  final verified = auth.verified.value;
  if (!verified) {
    return location == UsRoutes.verify ? null : UsRoutes.verify;
  }

  // Fully authenticated: bounce off the login/signup/... routes.
  if (isAuthRoute) return UsRoutes.home;

  return null;
}
