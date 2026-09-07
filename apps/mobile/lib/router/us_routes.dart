final class UsRoutes {
  const UsRoutes._();

  static const String onboarding = '/onboarding';

  static const String signup = '/signup';
  static const String login = '/login';
  static const String forgotPw = '/forgot-password';
  static const String resetPw = '/reset-password';
  static const String verify = '/verify';

  /// Builds the verification route, optionally carrying the pending account
  /// email (used when the user arrives from a rejected login rather than an
  /// active session) so the page can offer resend.
  static String verifyRoute({String? email}) {
    if (email == null || email.isEmpty) return verify;
    return '$verify?email=${Uri.encodeQueryComponent(email)}';
  }

  /// Builds the reset-password route carrying the email the code was sent to
  /// (for display and resend).
  static String resetPwRoute({String? email}) {
    if (email == null || email.isEmpty) return resetPw;
    return '$resetPw?email=${Uri.encodeQueryComponent(email)}';
  }

  static const String home = '/home';
  static const String listings = '/listings';
  static const String search = '/search';
  static const String sell = '/sell';
  static const String chat = '/chat';
  static const String profile = '/profile';

  static const String listingDetails = '/listings/:id';
  static const String settings = '/profile/settings';
  static const String editProfile = '/profile/edit';

  static String listingDetailsRoute(String id) => '/listings/$id';
}
