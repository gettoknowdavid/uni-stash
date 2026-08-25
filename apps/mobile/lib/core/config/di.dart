import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/api_client.dart';
import 'package:uni_stash_mobile/core/api/dio_client.dart';

final GetIt di = GetIt.instance;

/// Call once before at app startup.
///
/// After calling, `await di.allReady()` to ensure all async singletons
/// are initialised.
void configureDependencies() {
  // Logger — sync singleton, available immediately.
  di.registerSingleton<Logger>(Logger());

  // Dio — async singleton (reads secure-storage for auth token).
  di.registerSingletonAsync<Dio>(
    () => initDio(logger: di<Logger>()),
  );

  // Retrofit ApiClient — depends on Dio being ready.
  di.registerSingletonWithDependencies<ApiClient>(
    () => ApiClient(di<Dio>()),
    dependsOn: [Dio],
  );
}
