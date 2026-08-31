final class UsRoutes {
  const UsRoutes._();

  static const String onboarding = '/onboarding';

  static const String signup = '/signup';
  static const String login = '/login';
  static const String forgotPw = '/forgot-password';
  static const String resetPw = '/reset-password';
  static const String verify = '/verify';

  static const String home = '/home';
  static const String listings = '/listings';
  static const String search = '/search';
  static const String chat = '/chat';
  static const String profile = '/profile';

  static const String listingDetails = '/listings/:id';
  static const String settings = '/profile/settings';
  static const String editProfile = '/profile/edit';

  static String listingDetailsRoute(String id) => '/listings/$id';
}
