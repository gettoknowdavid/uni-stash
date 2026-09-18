import 'package:uni_stash_mobile/core/user/models.dart';

/// Credentials bundle used by the auth view model
/// to track the currently authenticated user.
class UserCredentials {
  const UserCredentials({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final User user;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}
