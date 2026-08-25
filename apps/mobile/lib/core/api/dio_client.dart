import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/auth/auth_store.dart';
import 'package:uni_stash_mobile/core/config/env.dart';

Future<Dio> initDio({
  required Logger logger,
  required FlutterSecureStorage storage,
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

  dio.interceptors.addAll([
    _AuthInterceptor(storage: storage, logger: logger),
    _LoggingInterceptor(logger),
  ]);

  return dio;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({
    required FlutterSecureStorage storage,
    required Logger logger,
  })  : _storage = storage,
        _logger = logger;

  final FlutterSecureStorage _storage;
  final Logger _logger;

  Completer<void>? _refreshCompleter;
  final Queue<_PendingRequest> _pendingQueue = Queue<_PendingRequest>();

  final _publicEndpoints = <String>[
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

    final token = await readAccessToken(_storage);
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

    if (_refreshCompleter != null) {
      final completer = Completer<void>();
      _pendingQueue.add(
        _PendingRequest(err.requestOptions, handler, completer),
      );
      await completer.future;
      return;
    }

    _refreshCompleter = Completer<void>();

    try {
      final refreshed = await _attemptRefresh();

      if (refreshed) {
        final retryResponse = await _retryRequest(err.requestOptions);
        handler.resolve(retryResponse);
        await _drainPendingQueue();
      } else {
        await markUnauthenticated(_storage);
        handler.next(err);
        _drainPendingQueueWithError(err);
      }
    } on Object catch (_) {
      await markUnauthenticated(_storage);
      handler.next(err);
      _drainPendingQueueWithError(err);
    } finally {
      _refreshCompleter!.complete();
      _refreshCompleter = null;
    }
  }

  Future<bool> _attemptRefresh() async {
    final refreshToken = await readRefreshToken(_storage);
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

    try {
      final response = await refreshDio.post<dynamic>(
        '/api/v1/auth/refresh',
        data: <String, dynamic>{'refresh_token': refreshToken},
      );

      if (response.statusCode == 200 &&
          response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;

        if (newAccess != null && newRefresh != null) {
          await markAuthenticated(
            _storage,
            accessToken: newAccess,
            refreshToken: newRefresh,
          );
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

  Future<Response<dynamic>> _retryRequest(
    RequestOptions requestOptions,
  ) async {
    final token = await readAccessToken(_storage);
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

    return retryDio.fetch<dynamic>(requestOptions);
  }

  Future<void> _drainPendingQueue() async {
    while (_pendingQueue.isNotEmpty) {
      final pending = _pendingQueue.removeFirst();

      try {
        final token = await readAccessToken(_storage);
        if (token != null && token.isNotEmpty) {
          pending.requestOptions.headers['Authorization'] =
              'Bearer $token';
        }

        final retryDio = Dio(
          BaseOptions(baseUrl: pending.requestOptions.baseUrl),
        );
        final response =
            await retryDio.fetch<dynamic>(pending.requestOptions);
        pending.handler.resolve(response);
      } on DioException catch (e) {
        pending.handler.next(e);
      } finally {
        pending.completer.complete();
      }
    }
  }

  void _drainPendingQueueWithError(DioException error) {
    while (_pendingQueue.isNotEmpty) {
      final pending = _pendingQueue.removeFirst();
      pending.handler.next(error);
      pending.completer.complete();
    }
  }
}

class _LoggingInterceptor extends Interceptor {
  _LoggingInterceptor(this._logger);

  final Logger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.d('[HTTP] ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.d(
      '[HTTP] ${response.statusCode} ${response.requestOptions.uri}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.e(
      '[HTTP] ${err.type.name} ${err.requestOptions.uri}',
      error: err.error,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }
}

class _PendingRequest {
  _PendingRequest(this.requestOptions, this.handler, this.completer);

  final RequestOptions requestOptions;
  final ErrorInterceptorHandler handler;
  final Completer<void> completer;
}
