import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';

class AuthRepository implements Disposable {
  AuthRepository(this._client);
  final AuthApiClient _client;

  // Future<LoginResponse> login(LoginRequest request) async {}

  @override
  FutureOr<dynamic> onDispose() {
    throw UnimplementedError();
  }
}
