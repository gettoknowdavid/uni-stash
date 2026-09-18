import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/user/models.dart';

class UserViewModel {
  final Signal<User?> _user = signal(null);

  /// Read-only view of the current user (null when signed out).
  ReadonlySignal<User?> get currentUser => _user;

  /// Called whenever the session changes.
  void setUser(User? user) => _user.value = user;

  void dispose() => _user.dispose();
}
