import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/view_models/reset_password_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepository;
  late ResetPasswordViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const ResetPasswordRequest(code: '123456', newPassword: 'newpassword123'),
    );
    registerFallbackValue(
      const ForgotPasswordRequest(email: 'test@university.edu'),
    );
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    viewModel = ResetPasswordViewModel(
      mockRepository,
      email: 'test@university.edu',
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('Initial State', () {
    test('signals start at their defaults', () {
      expect(viewModel.code.value, '');
      expect(viewModel.newPassword.value, '');
      expect(viewModel.confirmPassword.value, '');
      expect(viewModel.isLoading.value, isFalse);
      expect(viewModel.isResending.value, isFalse);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
      expect(viewModel.resendMessage.value, isNull);
    });
  });

  group('setters', () {
    test('setCode stores digits only', () {
      viewModel.setCode('12a-3456');
      expect(viewModel.code.value, '123456');
    });

    test('setCode with null keeps the code empty', () {
      viewModel.setCode('123456');
      viewModel.setCode(null);
      expect(viewModel.code.value, '');
    });

    test('setNewPassword/setConfirmPassword store the raw values', () {
      viewModel.setNewPassword('newpassword123');
      viewModel.setConfirmPassword('newpassword123');
      expect(viewModel.newPassword.value, 'newpassword123');
      expect(viewModel.confirmPassword.value, 'newpassword123');
    });
  });

  group('submit - Success', () {
    test('successful reset sets the result', () async {
      when(() => mockRepository.resetPassword(any())).thenAnswer(
        (_) async => const Result.success(null),
      );

      viewModel.setCode('123456');
      viewModel.setNewPassword('newpassword123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, isTrue);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, isFalse);
      verify(
        () => mockRepository.resetPassword(
          const ResetPasswordRequest(
            code: '123456',
            newPassword: 'newpassword123',
          ),
        ),
      ).called(1);
    });
  });

  group('submit - Failure', () {
    test('failed reset sets the error signal', () async {
      when(() => mockRepository.resetPassword(any())).thenAnswer(
        (_) async => const Result.failure('Invalid or expired code'),
      );

      viewModel.setCode('000000');
      viewModel.setNewPassword('newpassword123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Invalid or expired code');
      expect(viewModel.result.value, isNull);
      expect(viewModel.isLoading.value, isFalse);
    });
  });

  group('resend', () {
    test('resends the code via the forgot-password endpoint', () async {
      when(() => mockRepository.forgotPassword(any())).thenAnswer(
        (_) async => const Result.success(null),
      );

      viewModel.resend();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.resendMessage.value, contains('test@university.edu'));
      expect(viewModel.isResending.value, isFalse);
      verify(
        () => mockRepository.forgotPassword(
          const ForgotPasswordRequest(email: 'test@university.edu'),
        ),
      ).called(1);
    });

    test('failed resend sets the error signal', () async {
      when(() => mockRepository.forgotPassword(any())).thenAnswer(
        (_) async => const Result.failure('Too many requests'),
      );

      viewModel.resend();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Too many requests');
      expect(viewModel.resendMessage.value, isNull);
    });
  });

  group('reset', () {
    test('reset clears all signals to initial values', () async {
      viewModel.setCode('123456');
      viewModel.setNewPassword('newpassword123');
      viewModel.setConfirmPassword('newpassword123');

      viewModel.reset();

      expect(viewModel.code.value, '');
      expect(viewModel.newPassword.value, '');
      expect(viewModel.confirmPassword.value, '');
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
      expect(viewModel.resendMessage.value, isNull);
    });
  });
}
