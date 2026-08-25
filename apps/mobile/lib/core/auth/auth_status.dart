import 'package:signals_flutter/signals_flutter.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

final Signal<AuthStatus> authStatus = signal(AuthStatus.loading);
