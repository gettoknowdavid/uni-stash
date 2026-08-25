import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_client.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late ApiClient apiClient;

  setUp(() {
    mockDio = MockDio();
    when(() => mockDio.options).thenReturn(
      BaseOptions(baseUrl: 'https://api.example.com'),
    );
    apiClient = ApiClient(mockDio);
  });

  setUpAll(() {
    registerFallbackValue(RequestOptions());
  });

  Response<Map<String, dynamic>> makeResponse({
    required String path,
    required Map<String, dynamic> data,
    int statusCode = 200,
  }) {
    return Response<Map<String, dynamic>>(
      data: data,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: path),
    );
  }

  group('ApiClient', () {
    group('signUp', () {
      test('returns SignUpResponse with tokens on 201', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/signup',
            data: {
              'id': 'uuid-123',
              'email': 'test@university.edu',
              'display_name': 'Test User',
              'email_verified': false,
              'access_token': 'access_token_123',
              'refresh_token': 'refresh_token_123',
              'expires_in': 900,
            },
            statusCode: 201,
          ),
        );

        final result = await apiClient.signUp(
          const SignUpRequest(
            email: 'test@university.edu',
            password: 'password123',
            displayName: 'Test User',
          ),
        );

        expect(result.id, 'uuid-123');
        expect(result.email, 'test@university.edu');
        expect(result.displayName, 'Test User');
        expect(result.emailVerified, false);
        expect(result.accessToken, 'access_token_123');
        expect(result.refreshToken, 'refresh_token_123');
        expect(result.expiresIn, 900);
      });
    });

    group('login', () {
      test('returns LoginResponse with tokens', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/login',
            data: {
              'access_token': 'access_token_123',
              'refresh_token': 'refresh_token_123',
              'expires_in': 900,
            },
          ),
        );

        final result = await apiClient.login(
          const LoginRequest(
            email: 'test@university.edu',
            password: 'password123',
          ),
        );

        expect(result.accessToken, 'access_token_123');
        expect(result.refreshToken, 'refresh_token_123');
        expect(result.expiresIn, 900);
      });
    });

    group('verifyOtp', () {
      test('returns tokens for email_verify', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/verify-otp',
            data: {
              'verified': true,
              'access_token': 'token123',
              'refresh_token': 'refresh123',
              'expires_in': 900,
            },
          ),
        );

        final result = await apiClient.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
        );

        expect(result.verified, true);
        expect(result.accessToken, 'token123');
        expect(result.refreshToken, 'refresh123');
        expect(result.expiresIn, 900);
      });

      test('returns no tokens for password_reset', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/verify-otp',
            data: {'verified': true},
          ),
        );

        final result = await apiClient.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'password_reset'),
        );

        expect(result.verified, true);
        expect(result.accessToken, isNull);
        expect(result.refreshToken, isNull);
      });
    });

    group('resendVerification', () {
      test('returns message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/resend-verification',
            data: {'message': 'verification code sent'},
          ),
        );

        final result = await apiClient.resendVerification(
          const ResendVerificationRequest(email: 'test@university.edu'),
        );

        expect(result.message, 'verification code sent');
      });
    });

    group('forgotPassword', () {
      test('returns message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/forgot-password',
            data: {
              'message':
                  'if an account with that email exists,'
                  ' a reset code has been sent',
            },
          ),
        );

        final result = await apiClient.forgotPassword(
          const ForgotPasswordRequest(email: 'test@university.edu'),
        );

        expect(result.message, contains('reset code has been sent'));
      });
    });

    group('resetPassword', () {
      test('returns success message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/reset-password',
            data: {'message': 'password updated successfully'},
          ),
        );

        final result = await apiClient.resetPassword(
          const ResetPasswordRequest(
            code: '123456',
            newPassword: 'newpassword123',
          ),
        );

        expect(result.message, 'password updated successfully');
      });
    });

    group('refresh', () {
      test('returns new tokens', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/refresh',
            data: {
              'access_token': 'new_access',
              'refresh_token': 'new_refresh',
              'expires_in': 900,
            },
          ),
        );

        final result = await apiClient.refresh(
          const RefreshRequest(refreshToken: 'old_refresh'),
        );

        expect(result.accessToken, 'new_access');
        expect(result.refreshToken, 'new_refresh');
        expect(result.expiresIn, 900);
      });
    });

    group('logout', () {
      test('returns status ok', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/logout',
            data: {'status': 'ok'},
          ),
        );

        final result = await apiClient.logout(
          const LogoutRequest(refreshToken: 'token123'),
        );

        expect(result.status, 'ok');
      });
    });

    group('me', () {
      test('returns UserProfile', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeResponse(
            path: '/api/v1/auth/me',
            data: {
              'id': 'uuid-123',
              'email': 'test@university.edu',
              'display_name': 'Test User',
              'email_verified': true,
              'role': 'student',
            },
          ),
        );

        final result = await apiClient.me();

        expect(result.id, 'uuid-123');
        expect(result.email, 'test@university.edu');
        expect(result.displayName, 'Test User');
        expect(result.emailVerified, true);
        expect(result.role, 'student');
      });
    });
  });
}
