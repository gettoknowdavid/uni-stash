import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';

void main() {
  group('SignUpRequest', () {
    test('serializes to JSON with correct keys', () {
      const request = SignUpRequest(
        email: 'test@university.edu',
        password: 'password123',
        displayName: 'Test User',
      );

      final json = request.toJson();

      expect(json['email'], 'test@university.edu');
      expect(json['password'], 'password123');
      expect(json['display_name'], 'Test User');
    });

    test('deserializes from JSON with snake_case keys', () {
      final json = {
        'email': 'test@university.edu',
        'password': 'password123',
        'display_name': 'Test User',
      };

      final request = SignUpRequest.fromJson(json);

      expect(request.email, 'test@university.edu');
      expect(request.password, 'password123');
      expect(request.displayName, 'Test User');
    });

    test('roundtrip serialization preserves data', () {
      const original = SignUpRequest(
        email: 'test@university.edu',
        password: 'password123',
        displayName: 'Test User',
      );

      final restored = SignUpRequest.fromJson(original.toJson());

      expect(restored, original);
    });
  });

  group('LoginRequest', () {
    test('serializes to JSON', () {
      const request = LoginRequest(
        email: 'test@university.edu',
        password: 'password123',
      );

      final json = request.toJson();

      expect(json['email'], 'test@university.edu');
      expect(json['password'], 'password123');
    });

    test('deserializes from JSON', () {
      final json = {
        'email': 'test@university.edu',
        'password': 'password123',
      };

      final request = LoginRequest.fromJson(json);

      expect(request.email, 'test@university.edu');
      expect(request.password, 'password123');
    });
  });

  group('LoginResponse', () {
    test('deserializes from JSON with snake_case keys', () {
      final json = {
        'access_token': 'eyJhbGciOiJIUzI1NiIs...',
        'refresh_token': 'abc123def456',
        'expires_in': 900,
      };

      final response = LoginResponse.fromJson(json);

      expect(response.accessToken, 'eyJhbGciOiJIUzI1NiIs...');
      expect(response.refreshToken, 'abc123def456');
      expect(response.expiresIn, 900);
    });

    test('serializes to JSON with snake_case keys', () {
      const response = LoginResponse(
        accessToken: 'eyJhbGciOiJIUzI1NiIs...',
        refreshToken: 'abc123def456',
        expiresIn: 900,
      );

      final json = response.toJson();

      expect(json['access_token'], 'eyJhbGciOiJIUzI1NiIs...');
      expect(json['refresh_token'], 'abc123def456');
      expect(json['expires_in'], 900);
    });
  });

  group('SignUpResponse', () {
    test('deserializes from JSON with tokens', () {
      final json = {
        'id': 'uuid-123',
        'email': 'test@university.edu',
        'display_name': 'Test User',
        'email_verified': false,
        'access_token': 'access_token_123',
        'refresh_token': 'refresh_token_123',
        'expires_in': 900,
      };

      final response = SignUpResponse.fromJson(json);

      expect(response.id, 'uuid-123');
      expect(response.email, 'test@university.edu');
      expect(response.displayName, 'Test User');
      expect(response.emailVerified, false);
      expect(response.accessToken, 'access_token_123');
      expect(response.refreshToken, 'refresh_token_123');
      expect(response.expiresIn, 900);
    });

    test('deserializes without tokens', () {
      final json = {
        'id': 'uuid-123',
        'email': 'test@university.edu',
        'display_name': 'Test User',
        'email_verified': false,
      };

      final response = SignUpResponse.fromJson(json);

      expect(response.accessToken, isNull);
      expect(response.refreshToken, isNull);
      expect(response.expiresIn, isNull);
    });
  });

  group('VerifyOtpRequest', () {
    test('serializes to JSON with snake_case keys', () {
      const request = VerifyOtpRequest(
        code: '123456',
        otpType: 'email_verify',
      );

      final json = request.toJson();

      expect(json['code'], '123456');
      expect(json['otp_type'], 'email_verify');
    });

    test('deserializes from JSON', () {
      final json = {
        'code': '123456',
        'otp_type': 'password_reset',
      };

      final request = VerifyOtpRequest.fromJson(json);

      expect(request.code, '123456');
      expect(request.otpType, 'password_reset');
    });
  });

  group('VerifyOtpResponse', () {
    test('deserializes with optional token fields', () {
      final json = {
        'verified': true,
        'access_token': 'token123',
        'refresh_token': 'refresh123',
        'expires_in': 900,
      };

      final response = VerifyOtpResponse.fromJson(json);

      expect(response.verified, true);
      expect(response.accessToken, 'token123');
      expect(response.refreshToken, 'refresh123');
      expect(response.expiresIn, 900);
    });

    test('deserializes without token fields for password_reset', () {
      final json = {
        'verified': true,
      };

      final response = VerifyOtpResponse.fromJson(json);

      expect(response.verified, true);
      expect(response.accessToken, isNull);
      expect(response.refreshToken, isNull);
      expect(response.expiresIn, isNull);
    });
  });

  group('RefreshRequest', () {
    test('serializes to JSON with snake_case key', () {
      const request = RefreshRequest(refreshToken: 'refresh_token_123');

      final json = request.toJson();

      expect(json['refresh_token'], 'refresh_token_123');
    });

    test('deserializes from JSON', () {
      final json = {'refresh_token': 'refresh_token_123'};

      final request = RefreshRequest.fromJson(json);

      expect(request.refreshToken, 'refresh_token_123');
    });
  });

  group('RefreshResponse', () {
    test('deserializes from JSON', () {
      final json = {
        'access_token': 'new_access_token',
        'refresh_token': 'new_refresh_token',
        'expires_in': 900,
      };

      final response = RefreshResponse.fromJson(json);

      expect(response.accessToken, 'new_access_token');
      expect(response.refreshToken, 'new_refresh_token');
      expect(response.expiresIn, 900);
    });
  });

  group('MessageResponse', () {
    test('deserializes from JSON', () {
      final json = {'message': 'verification code sent'};

      final response = MessageResponse.fromJson(json);

      expect(response.message, 'verification code sent');
    });
  });

  group('LogoutRequest', () {
    test('serializes to JSON', () {
      const request = LogoutRequest(refreshToken: 'token123');

      final json = request.toJson();

      expect(json['refresh_token'], 'token123');
    });
  });

  group('LogoutResponse', () {
    test('deserializes from JSON', () {
      final json = {'status': 'ok'};

      final response = LogoutResponse.fromJson(json);

      expect(response.status, 'ok');
    });
  });

  group('UserProfile', () {
    test('deserializes from JSON', () {
      final json = {
        'id': 'uuid-123',
        'email': 'test@university.edu',
        'display_name': 'Test User',
        'email_verified': true,
        'role': 'student',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'uuid-123');
      expect(profile.email, 'test@university.edu');
      expect(profile.displayName, 'Test User');
      expect(profile.emailVerified, true);
      expect(profile.role, 'student');
    });
  });

  group('ResendVerificationRequest', () {
    test('serializes and deserializes', () {
      const request = ResendVerificationRequest(
        email: 'test@university.edu',
      );

      final restored = ResendVerificationRequest.fromJson(request.toJson());

      expect(restored, request);
    });
  });

  group('ForgotPasswordRequest', () {
    test('serializes and deserializes', () {
      const request = ForgotPasswordRequest(
        email: 'test@university.edu',
      );

      final restored = ForgotPasswordRequest.fromJson(request.toJson());

      expect(restored, request);
    });
  });

  group('ResetPasswordRequest', () {
    test('serializes to JSON with snake_case key', () {
      const request = ResetPasswordRequest(
        code: '123456',
        newPassword: 'newpassword123',
      );

      final json = request.toJson();

      expect(json['code'], '123456');
      expect(json['new_password'], 'newpassword123');
    });

    test('deserializes from JSON', () {
      final json = {
        'code': '123456',
        'new_password': 'newpassword123',
      };

      final request = ResetPasswordRequest.fromJson(json);

      expect(request.code, '123456');
      expect(request.newPassword, 'newpassword123');
    });
  });
}
