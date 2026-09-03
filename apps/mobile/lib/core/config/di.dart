import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_client.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

final GetIt di = GetIt.instance;

void configureDependencies() {
  _registerCore();
  _registerAuth();
}

/// App-wide infrastructure shared by every feature.
void _registerCore() {
  di.registerSingleton<FlutterSecureStorage>(const FlutterSecureStorage());
  di.registerSingleton<Logger>(Logger());

  // Dio is wired through callbacks rather than a direct AuthViewModel
  // dependency: the closures resolve `di<AuthViewModel>()` lazily, only when
  // a 401 is actually handled. That keeps the otherwise-circular graph
  // (Dio -> auth interceptor -> AuthViewModel -> AuthApiClient -> Dio) from
  // ever forming, since nothing is resolved at registration time.
  di.registerSingletonAsync<Dio>(
    () => initDio(
      logger: di<Logger>(),
      storage: di<FlutterSecureStorage>(),
      onSessionRefreshed: (credentials) =>
          di<AuthViewModel>().authenticate(credentials),
      onSessionExpired: () => di<AuthViewModel>().unauthenticate(),
    ),
  );
}

/// Auth feature registrations. Add `_register<Feature>()` helpers here as
/// listings/chats/etc. land, instead of growing this flat list.
void _registerAuth() {
  di.registerSingletonWithDependencies<AuthApiClient>(
    () => AuthApiClient(di<Dio>()),
    dependsOn: [Dio],
  );

  di.registerSingletonWithDependencies<IAuthRepository>(
    () => AuthRepository(di<AuthApiClient>(), di<Logger>()),
    dependsOn: [AuthApiClient],
  );

  di.registerSingletonWithDependencies<AuthViewModel>(
    () => AuthViewModel(di<IAuthRepository>(), di<FlutterSecureStorage>()),
    dependsOn: [IAuthRepository],
  );
}
