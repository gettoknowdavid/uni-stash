import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/config/env.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

/// Builds the app's shared [Dio] instance.
///
/// [onSessionRefreshed] is called with the new credentials after a 401
/// triggers a successful token refresh; [onSessionExpired] fires when a
/// refresh fails and the session must be treated as logged out.
///
/// Both are plain callbacks that the DI container wires to lazy closures
/// over the auth stack. `initDio` therefore never reaches into the service
/// locator itself, keeping the Dio -> interceptor -> AuthViewModel graph
/// acyclic and the interceptor unit-testable without a GetIt scope.
///
/// [httpClientAdapter] is optional and only used by tests to script
/// responses; production leaves it unset so Dio's default adapter is used.
Future<Dio> initDio({
  required Logger logger,
  required FlutterSecureStorage storage,
  required void Function(UserCredentials credentials) onSessionRefreshed,
  required void Function() onSessionExpired,
  HttpClientAdapter? httpClientAdapter,
}) async {
  final options = BaseOptions(
    baseUrl: Env.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  );

  final dio = Dio(options);
  if (httpClientAdapter != null) {
    dio.httpClientAdapter = httpClientAdapter;
  }

  dio.interceptors.addAll([
    _AuthInterceptor(
      storage: storage,
      logger: logger,
      onSessionRefreshed: onSessionRefreshed,
      onSessionExpired: onSessionExpired,
      httpClientAdapter: httpClientAdapter,
    ),
    _LoggingInterceptor(logger),
  ]);

  return dio;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({
    required FlutterSecureStorage storage,
    required Logger logger,
    required void Function(UserCredentials credentials) onSessionRefreshed,
    required void Function() onSessionExpired,
    HttpClientAdapter? httpClientAdapter,
  })  : _storage = storage,
        _logger = logger,
        _onSessionRefreshed = onSessionRefreshed,
        _onSessionExpired = onSessionExpired,
        _httpClientAdapter = httpClientAdapter;

  final FlutterSecureStorage _storage;
  final Logger _logger;
  final void Function(UserCredentials credentials) _onSessionRefreshed;
  final void Function() _onSessionExpired;
  final HttpClientAdapter? _httpClientAdapter;

  /// Non-null while a token refresh is in flight. Concurrent 401s await this
  /// same future rather than starting their own refresh, so at most one
  /// refresh request is ever issued per batch of 401s and no caller can be
  /// left waiting on a completer that never fires.
  Future<bool>? _inFlightRefresh;

  static const _publicEndpoints = <String>[
    '/auth/refresh',
    '/auth/login',
    '/auth/register',
    '/forgot-password',
  ];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_publicEndpoints.any((e) => options.path.contains(e))) {
      handler.next(options);
      return;
    }

    final token = await _storage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Share a single refresh across all concurrent 401s. `_refreshSession`
    // always completes (failures become `false`), so awaiting it can never
    // hang; `whenComplete` clears the slot for the next batch of 401s.
    final refresh = _inFlightRefresh ??= _refreshSession().whenComplete(
      () => _inFlightRefresh = null,
    );
    final refreshed = await refresh;

    if (refreshed) {
      handler.resolve(await _retryRequest(err.requestOptions));
    } else {
      handler.next(err);
    }
  }

  /// Runs one token-refresh attempt and reports the outcome.
  ///
  /// [_onSessionExpired] is invoked exactly once per attempt (from whichever
  /// caller started the shared refresh) so a batch of concurrent 401s does
  /// not clear the session repeatedly.
  Future<bool> _refreshSession() async {
    try {
      final refreshed = await _attemptRefresh();
      if (!refreshed) {
        _onSessionExpired();
      }
      return refreshed;
    } on Object {
      _onSessionExpired();
      return false;
    }
  }

  Future<bool> _attemptRefresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) {
      _logger.w('[Auth] No refresh token stored — cannot refresh');
      return false;
    }

    final refreshDio = Dio(
      BaseOptions(
        baseUrl: Env.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    if (_httpClientAdapter != null) {
      refreshDio.httpClientAdapter = _httpClientAdapter;
    }

    try {
      // Request the raw body and decode it explicitly: Dio only type-casts
      // generic responses (`post<T>` asserts the decoded JSON is already a
      // `T`), so asking it to build an `ApiResponse<RefreshResponse>` would
      // always throw before the payload could be inspected.
      final response = await refreshDio.post<String>(
        '/api/v1/auth/refresh',
        data: <String, dynamic>{'refresh_token': refreshToken},
      );
      if (response.statusCode == 200 && response.data != null) {
        final decoded = jsonDecode(response.data!);
        final envelope = ApiResponse<RefreshResponse>.fromJson(
          decoded as Map<String, dynamic>,
          (json) => RefreshResponse.fromJson(
            json! as Map<String, dynamic>,
          ),
        );
        final data = envelope.data;
        final newAccess = data?.accessToken;
        final newRefresh = data?.refreshToken;
        final user = data?.user;

        if (data != null &&
            newAccess != null &&
            newRefresh != null &&
            user != null) {
          final credentials = UserCredentials(
            user: user,
            accessToken: newAccess,
            refreshToken: newRefresh,
            expiresIn: data.expiresIn,
          );
          _onSessionRefreshed(credentials);
          _logger.d('[Auth] Token refresh succeeded');
          return true;
        }
      }

      _logger.w('[Auth] Refresh response missing tokens');
      return false;
    } on DioException catch (e) {
      _logger.e(
        '[Auth] Refresh request failed: ${e.type.name}',
        error: e.error,
      );
      return false;
    } finally {
      refreshDio.close();
    }
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions requestOptions) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      requestOptions.headers['Authorization'] = 'Bearer $token';
    }

    final retryDio = Dio(
      BaseOptions(
        baseUrl: requestOptions.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    if (_httpClientAdapter != null) {
      retryDio.httpClientAdapter = _httpClientAdapter;
    }

    return retryDio.fetch<dynamic>(requestOptions);
  }
}

class _LoggingInterceptor extends Interceptor {
  _LoggingInterceptor(this.logger);

  final Logger logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.d('[HTTP] ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    logger.d(
      '[HTTP] ${response.statusCode} ${response.requestOptions.uri}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e(
      '[HTTP] ${err.type.name} ${err.requestOptions.uri}',
      error: err.error,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }
}
