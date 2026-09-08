import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';

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
    user:
        user ??
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
    registerFallbackValue(
      const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
    );
    registerFallbackValue(
      const ResendVerificationRequest(email: ''),
    );
    registerFallbackValue(
      const ResetPasswordRequest(code: '123456', newPassword: 'newpassword'),
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
    test(
      'returns Success with LoginResponse when API returns valid data',
      () async {
        when(() => mockApiClient.login(any())).thenAnswer(
          (_) async => ApiResponse<LoginResponse>(
            status: true,
            message: 'ok',
            data: makeLoginResponse(),
          ),
        );

        const request = LoginRequest(
          email: 'test@example.com',
          password: 'password123',
        );
        final result = await repository.login(request);

        expect(result.isSuccess, true);
        if (result case Success(:final value)) {
          expect(value.accessToken, 'access_token_123');
          expect(value.user.email, 'test@example.com');
        }
        verify(() => mockApiClient.login(request)).called(1);
      },
    );
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
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'wrong@example.com', password: 'wrong'),
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
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('internet connection'));
      }
    });

    test('returns invalid credentials for 401', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 401,
          responseData: {'message': 'Invalid email or password'},
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Invalid email or password');
      }
    });

    test('returns already exists for 409', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 409,
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('already exists'));
      }
    });

    test('returns check input for 422', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 422,
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('check your input'));
      }
    });

    test('returns server error for 500', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 500,
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('Server error'));
      }
    });

    test('uses response body message when available', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 500,
          responseData: {'message': 'Custom server message'},
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Custom server message');
      }
    });

    test('reads messages from the nested error envelope', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 403,
          responseData: {
            'status': false,
            'data': null,
            'error': {
              'code': 'email_not_verified',
              'message': 'Email not verified',
              'fields': null,
            },
          },
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'new@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Email not verified');
      }
    });

    test('surfaces the backend error code for email_not_verified', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(
          statusCode: 403,
          responseData: {
            'status': false,
            'data': null,
            'error': {'code': 'email_not_verified', 'message': 'not verified'},
          },
        ),
      );

      final result = await repository.login(
        const LoginRequest(email: 'new@example.com', password: 'pass'),
      );

      expect(result.failureCode, AuthErrorCode.emailNotVerified);
      if (result case Failure(:final code)) {
        expect(code, 'email_not_verified');
      }
    });

    test('maps a bare 403 to the email-not-verified message', () async {
      when(() => mockApiClient.login(any())).thenThrow(
        makeDioException(statusCode: 403),
      );

      final result = await repository.login(
        const LoginRequest(email: 'new@example.com', password: 'pass'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('not verified'));
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
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
        const LoginRequest(email: 'test@example.com', password: 'pass'),
      );

      verify(
        () => mockLogger.e(
          '[AuthRepository] login unexpected error',
          error: any(named: 'error'),
        ),
      ).called(1);
    });
  });

  // =========================================================================
  // GROUP: verifyOtp
  // =========================================================================
  group('verifyOtp', () {
    test('returns tokens + verified user on success', () async {
      const user = User(
        id: 'uuid-789',
        email: 'test@university.edu',
        displayName: 'Test User',
        emailVerified: true,
        role: 'student',
      );
      when(() => mockApiClient.verifyOtp(any())).thenAnswer(
        (_) async => const ApiResponse<VerifyOtpResponse>(
          status: true,
          message: 'ok',
          data: VerifyOtpResponse(
            verified: true,
            accessToken: 'new_access',
            refreshToken: 'new_refresh',
            expiresIn: 900,
            user: user,
          ),
        ),
      );

      final result = await repository.verifyOtp(
        const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
      );

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.verified, isTrue);
        expect(value.accessToken, 'new_access');
        expect(value.user?.emailVerified, isTrue);
      }
      verify(
        () => mockApiClient.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
        ),
      ).called(1);
    });

    test('returns Failure for an invalid/expired code', () async {
      when(() => mockApiClient.verifyOtp(any())).thenThrow(
        makeDioException(
          statusCode: 400,
          responseData: {
            'error': {'code': 'bad_request', 'message': 'invalid OTP'},
          },
        ),
      );

      final result = await repository.verifyOtp(
        const VerifyOtpRequest(code: '000000', otpType: 'email_verify'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'invalid OTP');
      }
    });
  });

  // =========================================================================
  // GROUP: resendVerification
  // =========================================================================
  group('resendVerification', () {
    test('returns Success when the code is resent', () async {
      when(() => mockApiClient.resendVerification(any())).thenAnswer(
        (_) async => const ApiResponse<MessageResponse>(
          status: true,
          message: 'verification code sent',
        ),
      );

      final result = await repository.resendVerification(
        const ResendVerificationRequest(email: 'test@university.edu'),
      );

      expect(result.isSuccess, true);
      verify(
        () => mockApiClient.resendVerification(
          const ResendVerificationRequest(email: 'test@university.edu'),
        ),
      ).called(1);
    });

    test('returns Failure when the API reports an error', () async {
      when(() => mockApiClient.resendVerification(any())).thenAnswer(
        (_) async => const ApiResponse<MessageResponse>(
          status: false,
          message: 'email is already verified',
        ),
      );

      final result = await repository.resendVerification(
        const ResendVerificationRequest(email: 'test@university.edu'),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'email is already verified');
      }
    });
  });

  // =========================================================================
  // GROUP: resetPassword
  // =========================================================================
  group('resetPassword', () {
    test('returns Success when the password is updated', () async {
      when(() => mockApiClient.resetPassword(any())).thenAnswer(
        (_) async => const ApiResponse<MessageResponse>(
          status: true,
          message: 'password updated successfully',
        ),
      );

      final result = await repository.resetPassword(
        const ResetPasswordRequest(
          code: '123456',
          newPassword: 'newpassword123',
        ),
      );

      expect(result.isSuccess, true);
      verify(
        () => mockApiClient.resetPassword(
          const ResetPasswordRequest(
            code: '123456',
            newPassword: 'newpassword123',
          ),
        ),
      ).called(1);
    });

    test('returns Failure on a bad code', () async {
      when(() => mockApiClient.resetPassword(any())).thenThrow(
        makeDioException(
          statusCode: 400,
          responseData: {
            'error': {'code': 'bad_request', 'message': 'invalid OTP'},
          },
        ),
      );

      final result = await repository.resetPassword(
        const ResetPasswordRequest(
          code: '000000',
          newPassword: 'newpassword123',
        ),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'invalid OTP');
      }
    });
  });
}
