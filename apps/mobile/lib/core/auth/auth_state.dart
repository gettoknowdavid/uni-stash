import 'package:signals_flutter/signals_flutter.dart';

/// Represents the authentication status of the user.
///
/// - `loading` - The authentication status is being loaded.
/// - `authenticated` - The user is authenticated.
/// - `unauthenticated` - The user is not authenticated.
enum AuthStatus { loading, authenticated, unauthenticated }

final Signal<AuthStatus> authStatus = signal(AuthStatus.loading);
