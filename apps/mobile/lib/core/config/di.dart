import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_client.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';

final GetIt di = GetIt.instance;

void configureDependencies() {
  di.registerSingleton<FlutterSecureStorage>(const FlutterSecureStorage());
  di.registerSingleton<Logger>(Logger());

  di.registerSingletonAsync<Dio>(
    () => initDio(
      logger: di<Logger>(),
      storage: di<FlutterSecureStorage>(),
    ),
  );

  di.registerSingletonWithDependencies<AuthApiClient>(
    () => AuthApiClient(di<Dio>()),
    dependsOn: [Dio],
  );
}
