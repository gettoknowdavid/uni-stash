import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/verify_otp_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

VerifyOtpResponse makeVerifyOtpResponse() {
  return const VerifyOtpResponse(
    verified: true,
    accessToken: 'access_token_123',
    refreshToken: 'refresh_token_123',
    expiresIn: 900,
    user: User(
      id: 'test-uuid-123',
      email: 'test@university.edu',
      displayName: 'Test User',
      emailVerified: true,
      role: 'student',
    ),
  );
}

void main() {
  late MockAuthRepository mockRepository;
  late VerifyOtpViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
    );
    registerFallbackValue(
      const ResendVerificationRequest(email: ''),
    );
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    viewModel = VerifyOtpViewModel(
      mockRepository,
      email: 'test@university.edu',
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('Initial State', () {
    test('code signal starts empty', () {
      expect(viewModel.code.value, '');
    });

    test('loading signals start false', () {
      expect(viewModel.isLoading.value, isFalse);
      expect(viewModel.isResending.value, isFalse);
    });

    test('error/result/resendMessage signals start null', () {
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
      expect(viewModel.resendMessage.value, isNull);
    });
  });

  group('setCode', () {
    test('stores the digits as typed', () {
      viewModel.setCode('123456');
      expect(viewModel.code.value, '123456');
    });

    test('strips non-digit characters', () {
      viewModel.setCode('1a2-3 4.5b6');
      expect(viewModel.code.value, '123456');
    });

    test('setCode with null keeps the code empty', () {
      viewModel.setCode('123456');
      viewModel.setCode(null);
      expect(viewModel.code.value, '');
    });
  });

  group('submit - Success', () {
    test('successful verification sets result and clears error', () async {
      final response = makeVerifyOtpResponse();
      when(() => mockRepository.verifyOtp(any())).thenAnswer(
        (_) async => Result.success(response),
      );

      viewModel.setCode('123456');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, equals(response));
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, isFalse);

      verify(
        () => mockRepository.verifyOtp(
          const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
        ),
      ).called(1);
    });
  });

  group('submit - Failure', () {
    test('failed verification sets the error signal', () async {
      when(() => mockRepository.verifyOtp(any())).thenAnswer(
        (_) async => const Result.failure('Invalid or expired code'),
      );

      viewModel.setCode('000000');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Invalid or expired code');
      expect(viewModel.result.value, isNull);
      expect(viewModel.isLoading.value, isFalse);
    });
  });

  group('submit - Guards', () {
    test('ignores submit while already submitting', () async {
      final completer = Completer<Result<VerifyOtpResponse>>();
      when(() => mockRepository.verifyOtp(any())).thenAnswer(
        (_) => completer.future,
      );

      viewModel.setCode('123456');
      viewModel.submit();
      // Second submit while the first is in flight must be a no-op.
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      verify(() => mockRepository.verifyOtp(any())).called(1);
      completer.complete(Result.success(makeVerifyOtpResponse()));
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('resend', () {
    test('successful resend sets a confirmation message', () async {
      when(() => mockRepository.resendVerification(any())).thenAnswer(
        (_) async => const Result.success(null),
      );

      viewModel.resend();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.resendMessage.value, contains('test@university.edu'));
      expect(viewModel.error.value, isNull);
      expect(viewModel.isResending.value, isFalse);
      verify(
        () => mockRepository.resendVerification(
          const ResendVerificationRequest(email: 'test@university.edu'),
        ),
      ).called(1);
    });

    test('failed resend sets the error signal', () async {
      when(() => mockRepository.resendVerification(any())).thenAnswer(
        (_) async => const Result.failure('Email is already verified'),
      );

      viewModel.resend();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Email is already verified');
      expect(viewModel.resendMessage.value, isNull);
    });

    test('cannot resend without an email', () async {
      final emailless = VerifyOtpViewModel(mockRepository, email: '');

      emailless.resend();
      await Future<void>.delayed(Duration.zero);

      expect(emailless.error.value, contains('email address'));
      verifyNever(() => mockRepository.resendVerification(any()));
      emailless.dispose();
    });
  });

  group('reset', () {
    test('reset clears all signals to initial values', () async {
      viewModel.setCode('123456');
      when(() => mockRepository.verifyOtp(any())).thenAnswer(
        (_) async => Result.success(makeVerifyOtpResponse()),
      );
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      viewModel.reset();

      expect(viewModel.code.value, '');
      expect(viewModel.isLoading.value, isFalse);
      expect(viewModel.isResending.value, isFalse);
      expect(viewModel.error.value, isNull);
      expect(viewModel.resendMessage.value, isNull);
      expect(viewModel.result.value, isNull);
    });
  });
}
