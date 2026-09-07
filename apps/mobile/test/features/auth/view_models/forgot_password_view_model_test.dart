import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/view_models/forgot_password_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepository;
  late ForgotPasswordViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const ForgotPasswordRequest(email: 'test@university.edu'),
    );
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    viewModel = ForgotPasswordViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('Initial State', () {
    test('signals start at their defaults', () {
      expect(viewModel.email.value, '');
      expect(viewModel.isLoading.value, isFalse);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
    });
  });

  group('setEmail', () {
    test('setEmail updates the email signal', () {
      viewModel.setEmail('test@university.edu');
      expect(viewModel.email.value, 'test@university.edu');
    });

    test('setEmail with null sets empty string (null safety)', () {
      viewModel.setEmail('test@university.edu');
      viewModel.setEmail(null);
      expect(viewModel.email.value, '');
    });
  });

  group('submit - Success', () {
    test('successful request sets the result and clears error', () async {
      when(() => mockRepository.forgotPassword(any())).thenAnswer(
        (_) async => const Result.success(null),
      );

      viewModel.setEmail('test@university.edu');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, isTrue);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, isFalse);
      verify(
        () => mockRepository.forgotPassword(
          const ForgotPasswordRequest(email: 'test@university.edu'),
        ),
      ).called(1);
    });
  });

  group('submit - Failure', () {
    test('failed request sets the error signal', () async {
      when(() => mockRepository.forgotPassword(any())).thenAnswer(
        (_) async => const Result.failure('Too many requests'),
      );

      viewModel.setEmail('test@university.edu');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Too many requests');
      expect(viewModel.result.value, isNull);
      expect(viewModel.isLoading.value, isFalse);
    });
  });

  group('reset', () {
    test('reset clears all signals to initial values', () async {
      viewModel.setEmail('test@university.edu');

      viewModel.reset();

      expect(viewModel.email.value, '');
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
    });
  });
}
