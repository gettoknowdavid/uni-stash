import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_api.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late AuthApiClient authApi;

  setUp(() {
    mockDio = MockDio();
    when(() => mockDio.options).thenReturn(
      BaseOptions(baseUrl: 'https://api.example.com'),
    );
    authApi = AuthApiClient(mockDio);
  });

  setUpAll(() {
    registerFallbackValue(RequestOptions());
  });

  Response<Map<String, dynamic>> makeEnvelope({
    required String path,
    required Map<String, dynamic> data,
    int statusCode = 200,
  }) {
    return Response<Map<String, dynamic>>(
      data: {
        'status': true,
        'message': 'ok',
        'data': data,
      },
      statusCode: statusCode,
      requestOptions: RequestOptions(path: path),
    );
  }

  group('AuthApiClient', () {
    group('signUp', () {
      test('returns SignUpResponse with tokens and user on 201', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/signup',
            data: {
              'access_token': 'access_token_123',
              'refresh_token': 'refresh_token_123',
              'expires_in': 900,
              'user': {
                'id': 'uuid-123',
                'email': 'test@university.edu',
                'display_name': 'Test User',
                'email_verified': false,
                'role': 'student',
              },
            },
            statusCode: 201,
          ),
        );

        final result = await authApi.signUp(
          const SignUpRequest(
            email: 'test@university.edu',
            password: 'password123',
            displayName: 'Test User',
          ),
        );

        expect(result.status, true);
        expect(result.data?.accessToken, 'access_token_123');
        expect(result.data?.refreshToken, 'refresh_token_123');
        expect(result.data?.expiresIn, 900);
        expect(result.data?.user.id, 'uuid-123');
      });
    });

    group('login', () {
      test('returns LoginResponse with tokens and user', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/login',
            data: {
              'access_token': 'access_token_123',
              'refresh_token': 'refresh_token_123',
              'expires_in': 900,
              'user': {
                'id': 'uuid-456',
                'email': 'test@university.edu',
                'display_name': 'Test User',
                'email_verified': true,
                'role': 'student',
              },
            },
          ),
        );

        final result = await authApi.login(
          const LoginRequest(
            email: 'test@university.edu',
            password: 'password123',
          ),
        );

        expect(result.status, true);
        expect(result.data?.accessToken, 'access_token_123');
        expect(result.data?.refreshToken, 'refresh_token_123');
        expect(result.data?.expiresIn, 900);
        expect(result.data?.user.id, 'uuid-456');
      });
    });

    group('verifyOtp', () {
      test('returns tokens and user for email_verify', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/verify-otp',
            data: {
              'verified': true,
              'access_token': 'token123',
              'refresh_token': 'refresh123',
              'expires_in': 900,
              'user': {
                'id': 'uuid-789',
                'email': 'test@university.edu',
                'display_name': 'Test User',
                'email_verified': true,
                'role': 'student',
              },
            },
          ),
        );

        final result = await authApi.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
        );

        expect(result.status, true);
        expect(result.data?.verified, true);
        expect(result.data?.accessToken, 'token123');
        expect(result.data?.refreshToken, 'refresh123');
        expect(result.data?.user?.id, 'uuid-789');
      });

      test('returns no tokens for password_reset', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/verify-otp',
            data: {'verified': true},
          ),
        );

        final result = await authApi.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'password_reset'),
        );

        expect(result.status, true);
        expect(result.data?.verified, true);
        expect(result.data?.accessToken, isNull);
        expect(result.data?.refreshToken, isNull);
      });
    });

    group('resendVerification', () {
      test('returns message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/resend-verification',
            data: {'message': 'verification code sent'},
          ),
        );

        final result = await authApi.resendVerification(
          const ResendVerificationRequest(email: 'test@university.edu'),
        );

        expect(result.status, true);
        expect(result.data?.message, 'verification code sent');
      });
    });

    group('forgotPassword', () {
      test('returns message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/forgot-password',
            data: {
              'message':
                  'if an account with that email exists, '
                  'a reset code has been sent',
            },
          ),
        );

        final result = await authApi.forgotPassword(
          const ForgotPasswordRequest(email: 'test@university.edu'),
        );

        expect(result.status, true);
        expect(result.data?.message, contains('reset code has been sent'));
      });
    });

    group('resetPassword', () {
      test('returns success message', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/reset-password',
            data: {'message': 'password updated successfully'},
          ),
        );

        final result = await authApi.resetPassword(
          const ResetPasswordRequest(
            code: '123456',
            newPassword: 'newpassword123',
          ),
        );

        expect(result.status, true);
        expect(result.data?.message, 'password updated successfully');
      });
    });

    group('refresh', () {
      test('returns new tokens and user', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/refresh',
            data: {
              'access_token': 'new_access',
              'refresh_token': 'new_refresh',
              'expires_in': 900,
              'user': {
                'id': 'uuid-123',
                'email': 'test@university.edu',
                'display_name': 'Test User',
                'email_verified': true,
                'role': 'student',
              },
            },
          ),
        );

        final result = await authApi.refresh(
          const RefreshRequest(refreshToken: 'old_refresh'),
        );

        expect(result.status, true);
        expect(result.data?.accessToken, 'new_access');
        expect(result.data?.refreshToken, 'new_refresh');
        expect(result.data?.expiresIn, 900);
        expect(result.data?.user.id, 'uuid-123');
      });
    });

    group('logout', () {
      test('returns status ok', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
            path: '/api/v1/auth/logout',
            data: {'status': 'ok'},
          ),
        );

        final result = await authApi.logout(
          const LogoutRequest(refreshToken: 'token123'),
        );

        expect(result.status, true);
        expect(result.data?.status, 'ok');
      });
    });

    group('me', () {
      test('returns UserProfile', () async {
        when(() => mockDio.fetch<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => makeEnvelope(
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

        final result = await authApi.me();

        expect(result.status, true);
        expect(result.data?.id, 'uuid-123');
        expect(result.data?.email, 'test@university.edu');
        expect(result.data?.displayName, 'Test User');
        expect(result.data?.emailVerified, true);
        expect(result.data?.role, 'student');
      });
    });
  });
}
