import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/core/result/result.dart';

/// Mock classes for isolating the repository from real API and logger.
class MockAuthApiClient extends Mock implements AuthApiClient {}

class MockLogger extends Mock implements Logger {}

/// Creates a [LoginResponse] with sensible defaults.
LoginResponse makeLoginResponse({
  String? accessToken,
  String? refreshToken,
  int? expiresIn,
  User? user,
}) {
  return LoginResponse(
    accessToken: accessToken ?? 'access_token_123',
    refreshToken: refreshToken ?? 'refresh_token_123',
    expiresIn: expiresIn ?? 900,
    user: user ??
        const User(
          id: 'uuid-123',
          email: 'test@example.com',
          displayName: 'Test User',
          emailVerified: true,
          role: 'student',
        ),
  );
}

/// Creates a [DioException] with customizable properties.
DioException makeDioException({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? responseData,
}) {
  return DioException(
    type: type,
    requestOptions: RequestOptions(path: '/api/v1/auth/login'),
    response: (responseData != null || statusCode != null)
        ? Response(
            data: responseData,
            statusCode: statusCode,
            requestOptions: RequestOptions(path: '/api/v1/auth/login'),
          )
        : null,
  );
}

void main() {
  late MockAuthApiClient mockApiClient;
  late MockLogger mockLogger;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(
      const LoginRequest(email: '', password: ''),
    );
  });

  setUp(() {
    mockApiClient = MockAuthApiClient();
    mockLogger = MockLogger();
    repository = AuthRepository(mockApiClient, mockLogger);
  });

  // =========================================================================
  // GROUP: login - Success
  // =========================================================================
  group('login - Success', () {
    test('returns Success with LoginResponse when API returns valid data',
        () async {
      when(() => mockApiClient.login(any())).thenAnswer(
        (_) async => ApiResponse<LoginResponse>(
          status: true,
          message: 'ok',
          data: makeLoginResponse(),
        ),
      );

      final request =
          LoginRequest(email: 'test@example.com', password: 'password123');
      final result = await repository.login(request);

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.accessToken, 'access_token_123');
        expect(value.user.email, 'test@example.com');
      }
      verify(() => mockApiClient.login(request)).called(1);
    });
  });

  // =========================================================================
  // GROUP: login - API Failures (status is false or data is null)
  // =========================================================================
  group('login - API Failures', () {
    test('returns Failure when API status is false', () async {
      when(() => mockApiClient.login(any())).thenAnswer(
        (_) async => const ApiResponse<LoginResponse>(
          status: false,
          message: 'Invalid credentials',
          data: null,
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'wrong@example.com', password: 'wrong'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Invalid credentials');
      }
    });

    test('returns Failure when API data is null', () async {
      when(() => mockApiClient.login(any())).thenAnswer(
        (_) async => const ApiResponse<LoginResponse>(
          status: true,
          message: 'ok',
          data: null,
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'No data');
      }
    });
  });

  // =========================================================================
  // GROUP: login - Network Errors (DioException types)
  // =========================================================================
  group('login - Network Errors', () {
    test('returns timeout for connection timeout', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(type: DioExceptionType.connectionTimeout),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('timed out'));
      }
    });

    test('returns timeout for send timeout', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(type: DioExceptionType.sendTimeout),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('timed out'));
      }
    });

    test('returns timeout for receive timeout', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(type: DioExceptionType.receiveTimeout),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('timed out'));
      }
    });

    test('returns connection error for no internet', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('internet connection'));
      }
    });

    test('returns invalid credentials for 401', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          type: DioExceptionType.badResponse,
          statusCode: 401,
          responseData: {'message': 'Invalid email or password'},
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Invalid email or password');
      }
    });

    test('returns already exists for 409', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          type: DioExceptionType.badResponse,
          statusCode: 409,
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('already exists'));
      }
    });

    test('returns check input for 422', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          type: DioExceptionType.badResponse,
          statusCode: 422,
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('check your input'));
      }
    });

    test('returns server error for 500', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          type: DioExceptionType.badResponse,
          statusCode: 500,
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('Server error'));
      }
    });

    test('uses response body message when available', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          type: DioExceptionType.badResponse,
          statusCode: 500,
          responseData: {'message': 'Custom server message'},
        ),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Custom server message');
      }
    });
  });

  // =========================================================================
  // GROUP: login - Unexpected Errors (non-Dio)
  // =========================================================================
  group('login - Unexpected Errors', () {
    test('returns generic message for non-Dio exceptions', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        Exception('Something unexpected'),
      );

      final result = await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'An unexpected error occurred.');
      }
    });
  });

  // =========================================================================
  // GROUP: Logging
  // =========================================================================
  group('Logging', () {
    test('logs DioException errors for debugging', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      verify(
        () => mockLogger.e(
          '[AuthRepository] login failed',
          error: any(named: 'error'),
        ),
      ).called(1);
    });

    test('logs unexpected errors for debugging', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        Exception('Unexpected'),
      );

      await repository.login(
        LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      verify(
        () => mockLogger.e(
          '[AuthRepository] login unexpected error',
          error: any(named: 'error'),
        ),
      ).called(1);
    });
  });
}
