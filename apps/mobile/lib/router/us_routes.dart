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

  static const String home = '/';
  static const String schools = '/schools';
  static const String listings = '/listings';
  static const String search = '/search';
  static const String sell = '/sell';
  static const String chat = '/chat';

  /// Full-screen chat conversation (guide 7.8), pushed above the shell.
  static const String chatDetail = '/chat/:id';
  static const String profile = '/profile';

  static const String listingDetails = '/listings/:id';
  static const String settings = '/profile/settings';
  static const String editProfile = '/profile/edit';
  static const String listingEditor = '/listings/editor';
  static const String listingEdit = '/listings/:id/edit';

  /// Sale-history screens (guide 6.9/6.10).
  static const String myPurchases = '/sales/purchases';
  static const String mySales = '/sales/mine';

  /// Profile listing management + bookmarks.
  static const String myListings = '/profile/listings';
  static const String savedItems = '/profile/saved';
  static const String support = '/profile/support';
  static const String myReports = '/profile/reports';

  /// In-app notifications inbox (header bell).
  static const String notifications = '/notifications';

  /// Blocked users management (settings).
  static const String blockedUsers = '/profile/blocked';

  /// Legal pages (Settings → LEGAL, signup footer).
  static const String terms = '/legal/terms';
  static const String privacy = '/legal/privacy';

  static String listingDetailsRoute(String id) => '/listings/$id';
  static String listingEditRoute(String id) => '/listings/$id/edit';
  static String chatDetailRoute(String id) => '/chat/$id';
}
