import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';

class MockAuthApiClient extends Mock implements AuthApiClient {}

class MockLogger extends Mock implements Logger {}

User makeUser({String id = 'user-1'}) {
  return User(
    id: id,
    email: 'ada@unilag.edu.ng',
    displayName: 'Ada Lovelace',
    emailVerified: true,
    role: 'student',
  );
}

DioException makeDioException({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? responseData,
}) {
  return DioException(
    type: type,
    requestOptions: RequestOptions(path: '/api/v1/auth/me'),
    response: (responseData != null || statusCode != null)
        ? Response(
            data: responseData,
            statusCode: statusCode,
            requestOptions: RequestOptions(path: '/api/v1/auth/me'),
          )
        : null,
  );
}

void main() {
  late MockAuthApiClient mockApiClient;
  late MockLogger mockLogger;
  late ProfileRepositoryImpl repository;

  setUp(() {
    mockApiClient = MockAuthApiClient();
    mockLogger = MockLogger();
    repository = ProfileRepositoryImpl(mockApiClient, mockLogger);
  });

  group('getProfile', () {
    test('returns Success with User', () async {
      final user = makeUser();
      when(() => mockApiClient.me()).thenAnswer(
        (_) async => ApiResponse<User>(
          status: true,
          message: 'ok',
          data: user,
        ),
      );

      final result = await repository.getProfile();

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.id, 'user-1');
        expect(value.email, 'ada@unilag.edu.ng');
        expect(value.displayName, 'Ada Lovelace');
        expect(value.emailVerified, true);
        expect(value.role, 'student');
      }
    });

    test('calls the auth API client me() endpoint', () async {
      when(() => mockApiClient.me()).thenAnswer(
        (_) async => ApiResponse<User>(
          status: true,
          message: 'ok',
          data: makeUser(),
        ),
      );

      await repository.getProfile();

      verify(() => mockApiClient.me()).called(1);
    });

    test('returns Failure when API status is false', () async {
      when(() => mockApiClient.me()).thenAnswer(
        (_) async => const ApiResponse<User>(
          status: false,
          message: 'Unauthorized',
        ),
      );

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Unauthorized');
      }
    });

    test('returns Failure when API returns no data', () async {
      when(() => mockApiClient.me()).thenAnswer(
        (_) async => const ApiResponse<User>(
          status: true,
          message: 'ok',
        ),
      );

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'No data');
      }
    });

    test('returns Failure on DioException', () async {
      when(() => mockApiClient.me()).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('internet connection'));
      }
    });

    test('humanizes badResponse status codes', () async {
      when(() => mockApiClient.me()).thenThrow(
        makeDioException(statusCode: 401),
      );

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Invalid email or password.');
      }
    });

    test('extracts backend error message from the error envelope', () async {
      when(() => mockApiClient.me()).thenThrow(
        makeDioException(
          statusCode: 401,
          responseData: {
            'error': {'code': 'session_expired', 'message': 'Session expired.'},
          },
        ),
      );

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      expect(result.failureCode, 'session_expired');
      if (result case Failure(:final message)) {
        expect(message, 'Session expired.');
      }
    });

    test('returns generic failure on unexpected error', () async {
      when(() => mockApiClient.me()).thenThrow(Exception('kaboom'));

      final result = await repository.getProfile();

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'An unexpected error occurred.');
      }
    });
  });

  group('Logging', () {
    test('logs DioException errors', () async {
      when(() => mockApiClient.me()).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      await repository.getProfile();

      verify(
        () => mockLogger.e(
          '[ProfileRepository] getProfile failed',
          error: any(named: 'error'),
        ),
      ).called(1);
    });

    test('logs unexpected errors', () async {
      when(() => mockApiClient.me()).thenThrow(Exception('unexpected'));

      await repository.getProfile();

      verify(
        () => mockLogger.e(
          '[ProfileRepository] getProfile unexpected error',
          error: any(named: 'error'),
        ),
      ).called(1);
    });
  });
}
