import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/dio_client.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

class _MockLogger extends Mock implements Logger {}

/// Immutable snapshot of a request, so later header mutations on the shared
/// [RequestOptions] object don't rewrite history.
class _RecordedRequest {
  _RecordedRequest(RequestOptions options)
    : path = options.path,
      headers = Map<String, dynamic>.from(options.headers);

  final String path;
  final Map<String, dynamic> headers;
}

/// Adapter that hands each request to [script]; records a snapshot of every
/// request so tests can assert on how many times an endpoint was hit.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final FutureOr<ResponseBody> Function(RequestOptions request, int index)
      script;
  final List<_RecordedRequest> requests = [];
  int _count = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(_RecordedRequest(options));
    return script(options, _count++);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(String body, int statusCode) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// Mirrors the backend `ApiResponse` envelope used by every auth endpoint.
String _envelope(String dataJson) =>
    '{"status": true, "message": "ok", "data": $dataJson}';

const _userJson =
    '{"id": "u-1", "email": "a@university.edu", '
    '"display_name": "A", "email_verified": true, "role": "student"}';

void main() {
  late _MockStorage storage;
  late _MockLogger logger;
  late String? storedAccessToken;
  late String? storedRefreshToken;
  late List<UserCredentials> refreshedCredentials;
  late int sessionExpiredCount;

  setUp(() {
    storage = _MockStorage();
    logger = _MockLogger();
    storedAccessToken = 'old_access';
    storedRefreshToken = 'old_refresh';
    refreshedCredentials = [];
    sessionExpiredCount = 0;

    when(() => storage.read(key: any(named: 'key'))).thenAnswer((inv) async {
      final key = inv.namedArguments[#key] as String;
      return switch (key) {
        'access_token' => storedAccessToken,
        'refresh_token' => storedRefreshToken,
        _ => null,
      };
    });
    when(
      () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
    ).thenAnswer((inv) async {
      final key = inv.namedArguments[#key] as String;
      final value = inv.namedArguments[#value] as String?;
      if (key == 'access_token') storedAccessToken = value;
      if (key == 'refresh_token') storedRefreshToken = value;
    });
  });

  Future<DioException> expectDioError(Future<Response<dynamic>> future) async {
    try {
      await future;
      fail('expected a DioException');
    } on DioException catch (e) {
      return e;
    }
  }

  Future<Dio> buildDio(_ScriptedAdapter adapter) {
    return initDio(
      logger: logger,
      storage: storage,
      onSessionRefreshed: (credentials) {
        refreshedCredentials.add(credentials);
        // Mimic AuthViewModel.authenticate persisting the fresh tokens.
        storedAccessToken = credentials.accessToken;
        storedRefreshToken = credentials.refreshToken;
      },
      onSessionExpired: () => sessionExpiredCount++,
      httpClientAdapter: adapter,
    );
  }

  group('_AuthInterceptor', () {
    test(
      'concurrent 401s share one refresh and both retry with the new token',
      () async {
        final adapter = _ScriptedAdapter((request, index) async {
          if (request.path.contains('/api/v1/auth/refresh')) {
            // Keep the refresh in flight long enough for both 401s to queue.
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return _jsonResponse(
              _envelope(
                '{"access_token": "new_access", '
                '"refresh_token": "new_refresh", '
                '"expires_in": 900, "user": $_userJson}',
              ),
              200,
            );
          }
          final auth = request.headers['Authorization'] as String?;
          if (auth == 'Bearer new_access') {
            return _jsonResponse('{"ok": true}', 200);
          }
          return _jsonResponse(
            '{"status": false, "message": "expired", "data": null}',
            401,
          );
        });
        final dio = await buildDio(adapter);

        final results = await Future.wait([
          dio.get<Map<String, dynamic>>('/api/v1/me'),
          dio.get<Map<String, dynamic>>('/api/v1/me'),
        ]);

        expect(results, hasLength(2));
        for (final response in results) {
          expect(response.statusCode, 200);
          expect(response.data, {'ok': true});
        }

        final refreshHits = adapter.requests
            .where((r) => r.path.contains('/api/v1/auth/refresh'))
            .length;
        expect(refreshHits, 1, reason: 'only one refresh for the whole batch');

        expect(refreshedCredentials, hasLength(1));
        final credentials = refreshedCredentials.single;
        expect(credentials.accessToken, 'new_access');
        expect(credentials.refreshToken, 'new_refresh');
        expect(credentials.user.id, 'u-1');

        expect(sessionExpiredCount, 0);
      },
    );

    test('failed refresh expires the session exactly once per batch', () async {
      final adapter = _ScriptedAdapter((request, index) async {
        if (request.path.contains('/api/v1/auth/refresh')) {
          // Keep the failing refresh in flight so both 401s queue on it.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponse('{"status": false, "message": "nope"}', 401);
        }
        return _jsonResponse(
          '{"status": false, "message": "expired", "data": null}',
          401,
        );
      });
      final dio = await buildDio(adapter);

      final results = await Future.wait([
        expectDioError(dio.get('/api/v1/me')),
        expectDioError(dio.get('/api/v1/me')),
      ]);

      for (final error in results) {
        expect(error, isA<DioException>());
        expect(error.response?.statusCode, 401);
      }

      final refreshHits = adapter.requests
          .where((r) => r.path.contains('/api/v1/auth/refresh'))
          .length;
      expect(refreshHits, 1, reason: 'one refresh attempt for the whole batch');
      expect(refreshedCredentials, isEmpty);
      expect(sessionExpiredCount, 1, reason: 'one expiry per failed batch');
    });

    test('non-401 errors pass through without touching the session', () async {
      final adapter = _ScriptedAdapter((request, index) {
        return _jsonResponse('{"status": false, "message": "boom"}', 500);
      });
      final dio = await buildDio(adapter);

      final error = await expectDioError(dio.get('/api/v1/me'));

      expect(error.response?.statusCode, 500);
      expect(adapter.requests, hasLength(1));
      expect(refreshedCredentials, isEmpty);
      expect(sessionExpiredCount, 0);
    });

    test('retries use the Authorization header of the refreshed token',
        () async {
      final adapter = _ScriptedAdapter((request, index) {
        if (request.path.contains('/api/v1/auth/refresh')) {
          return _jsonResponse(
            _envelope(
              '{"access_token": "new_access", '
              '"refresh_token": "new_refresh", '
              '"expires_in": 900, "user": $_userJson}',
            ),
            200,
          );
        }
        final auth = request.headers['Authorization'] as String?;
        if (auth == 'Bearer new_access') {
          return _jsonResponse('{"ok": true}', 200);
        }
        return _jsonResponse('{"status": false, "message": "expired"}', 401);
      });
      final dio = await buildDio(adapter);

      final response = await dio.get<Map<String, dynamic>>('/api/v1/me');

      expect(response.statusCode, 200);
      final attempts = adapter.requests
          .where((r) => !r.path.contains('/api/v1/auth/refresh'))
          .toList();
      expect(attempts, hasLength(2));
      expect(attempts.first.headers['Authorization'], 'Bearer old_access');
      expect(attempts.last.headers['Authorization'], 'Bearer new_access');
      expect(sessionExpiredCount, 0);
    });
  });
}
