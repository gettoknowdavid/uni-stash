import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_client.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_api.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_api.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';

final GetIt di = GetIt.instance;

void configureDependencies() {
  _registerCore();
  _registerAuth();
  _registerListings();
  _registerSchools();
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
      onSessionExpired: () => di<AuthViewModel>().unauthenticate(),
      onSessionRefreshed: (credentials) => di<AuthViewModel>().authenticate(
        credentials,
      ),
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

  // The page-scoped auth view models (LoginViewModel, SignUpViewModel,
  // ForgotPasswordViewModel, VerifyOtpViewModel, ResetPasswordViewModel) are
  // intentionally NOT registered here. Each auth page pushes its own GetIt
  // scope in initState, registers its view model there, and pops the scope in
  // dispose, so every visit gets a fresh instance whose lifecycle (and
  // disposal) is owned by GetIt — see login_page.dart / signup_page.dart.
}

/// Listings feature registrations. The page-scoped ViewModels
/// (ListingsViewModel, ListingDetailViewModel) are registered per-page in
/// their respective initState, following the same pattern as auth.
void _registerListings() {
  di.registerSingletonWithDependencies<ListingsApiClient>(
    () => ListingsApiClient(di<Dio>()),
    dependsOn: [Dio],
  );

  di.registerSingletonWithDependencies<ListingsRepository>(
    () => ListingsRepositoryImpl(di<ListingsApiClient>(), di<Logger>()),
    dependsOn: [ListingsApiClient],
  );
}

/// Schools feature registrations. The page-scoped ViewModels
/// (SchoolsViewModel, SchoolDetailViewModel) are registered per-page in
/// their respective initState, following the same pattern as auth/listings.
void _registerSchools() {
  di.registerSingletonWithDependencies<SchoolsApiClient>(
    () => SchoolsApiClient(di<Dio>()),
    dependsOn: [Dio],
  );

  di.registerSingletonWithDependencies<SchoolsRepository>(
    () => SchoolsRepositoryImpl(di<SchoolsApiClient>(), di<Logger>()),
    dependsOn: [SchoolsApiClient],
  );
}
