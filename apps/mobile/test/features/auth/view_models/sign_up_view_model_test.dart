import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/sign_up_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

SignUpResponse makeSignUpResponse({
  User? user,
  String? accessToken,
  String? refreshToken,
  int? expiresIn,
}) {
  return SignUpResponse(
    user:
        user ??
        const User(
          id: 'test-uuid-123',
          email: 'test@university.edu',
          displayName: 'Test User',
          emailVerified: false,
          role: 'student',
        ),
    accessToken: accessToken ?? 'test_access_token',
    refreshToken: refreshToken ?? 'test_refresh_token',
    expiresIn: expiresIn ?? 900,
  );
}

void main() {
  late MockAuthRepository mockRepository;
  late SignUpViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const SignUpRequest(
        email: '',
        password: '',
        displayName: '',
      ),
    );
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    viewModel = SignUpViewModel(mockRepository);
  });

  tearDown(() async {
    await viewModel.onDispose();
  });

  // =========================================================================
  // GROUP: Initial State
  // =========================================================================
  group('Initial State', () {
    test('displayName signal starts as empty string', () {
      expect(viewModel.displayName.value, '');
    });

    test('email signal starts as empty string', () {
      expect(viewModel.email.value, '');
    });

    test('password signal starts as empty string', () {
      expect(viewModel.password.value, '');
    });

    test('confirmPassword signal starts as empty string', () {
      expect(viewModel.confirmPassword.value, '');
    });

    test('isLoading signal starts as false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('error signal starts as null', () {
      expect(viewModel.error.value, isNull);
    });

    test('result signal starts as null', () {
      expect(viewModel.result.value, isNull);
    });
  });

  // =========================================================================
  // GROUP: Setters
  // =========================================================================
  group('Setters', () {
    test('setDisplayName updates displayName signal', () {
      viewModel.setDisplayName('John Doe');
      expect(viewModel.displayName.value, 'John Doe');
    });

    test('setDisplayName with null sets empty string', () {
      viewModel.setDisplayName('John Doe');
      viewModel.setDisplayName(null);
      expect(viewModel.displayName.value, '');
    });

    test('setEmail updates email signal', () {
      viewModel.setEmail('test@university.edu');
      expect(viewModel.email.value, 'test@university.edu');
    });

    test('setEmail with null sets empty string', () {
      viewModel.setEmail('test@university.edu');
      viewModel.setEmail(null);
      expect(viewModel.email.value, '');
    });

    test('setPassword updates password signal', () {
      viewModel.setPassword('secret123');
      expect(viewModel.password.value, 'secret123');
    });

    test('setPassword with null sets empty string', () {
      viewModel.setPassword('secret123');
      viewModel.setPassword(null);
      expect(viewModel.password.value, '');
    });

    test('setConfirmPassword updates confirmPassword signal', () {
      viewModel.setConfirmPassword('secret123');
      expect(viewModel.confirmPassword.value, 'secret123');
    });

    test('setConfirmPassword with null sets empty string', () {
      viewModel.setConfirmPassword('secret123');
      viewModel.setConfirmPassword(null);
      expect(viewModel.confirmPassword.value, '');
    });
  });

  // =========================================================================
  // GROUP: submit - Success
  // =========================================================================
  group('submit - Success', () {
    test('successful signup sets result signal and clears error', () async {
      final signUpResponse = makeSignUpResponse();
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => Result.success(signUpResponse),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, equals(signUpResponse));
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);

      verify(() => mockRepository.signUp(any())).called(1);
    });

    test('isLoading goes true then false during submission', () async {
      when(() => mockRepository.signUp(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return Result.success(makeSignUpResponse());
      });

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      expect(viewModel.isLoading.value, true);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(viewModel.isLoading.value, false);
    });

    test('successful signup with null optional tokens', () async {
      const signUpResponse = SignUpResponse(
        user: User(
          id: 'test-uuid-123',
          email: 'test@university.edu',
          displayName: 'Test User',
          emailVerified: false,
          role: 'student',
        ),
      );
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => Result.success(signUpResponse),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, equals(signUpResponse));
      expect(viewModel.result.value?.accessToken, isNull);
      expect(viewModel.result.value?.refreshToken, isNull);
      expect(viewModel.result.value?.expiresIn, isNull);
    });
  });

  // =========================================================================
  // GROUP: submit - Failure
  // =========================================================================
  group('submit - Failure', () {
    test('failed signup sets error signal', () async {
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => const Result.failure('Account already exists'),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('existing@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Account already exists');
      expect(viewModel.result.value, isNull);
    });

    test('network timeout sets timeout message', () async {
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => const Result.failure(
          'Connection timed out. Please check your network.',
        ),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, contains('timed out'));
    });

    test('server error sets server error message', () async {
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => const Result.failure(
          'Server error (500). Please try again later.',
        ),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, contains('Server error'));
    });
  });

  // =========================================================================
  // GROUP: submit - Clears Previous State
  // =========================================================================
  group('submit - Clears Previous State', () {
    test('submit clears previous error on success', () async {
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => const Result.failure('First error'),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, 'First error');

      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => Result.success(makeSignUpResponse()),
      );

      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNotNull);
    });
  });

  // =========================================================================
  // GROUP: reset
  // =========================================================================
  group('reset', () {
    test('reset clears all signals to initial values', () {
      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.setConfirmPassword('password123');

      viewModel.reset();

      expect(viewModel.displayName.value, '');
      expect(viewModel.email.value, '');
      expect(viewModel.password.value, '');
      expect(viewModel.confirmPassword.value, '');
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
    });

    test('reset after failed signup clears error', () async {
      when(() => mockRepository.signUp(any())).thenAnswer(
        (_) async => const Result.failure('Error'),
      );

      viewModel.setDisplayName('Test User');
      viewModel.setEmail('test@university.edu');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, 'Error');

      viewModel.reset();
      expect(viewModel.error.value, isNull);
    });
  });

  // =========================================================================
  // GROUP: Signal Reactivity
  // =========================================================================
  group('Signal Reactivity', () {
    test('displayName signal notifies listeners when changed', () {
      String? capturedValue;
      final dispose = viewModel.displayName.subscribe((value) {
        capturedValue = value;
      });
      viewModel.setDisplayName('New Name');
      expect(capturedValue, 'New Name');
      dispose();
    });

    test('email signal notifies listeners when changed', () {
      String? capturedValue;
      final dispose = viewModel.email.subscribe((value) {
        capturedValue = value;
      });
      viewModel.setEmail('new@example.com');
      expect(capturedValue, 'new@example.com');
      dispose();
    });

    test('password signal notifies listeners when changed', () {
      String? capturedValue;
      final dispose = viewModel.password.subscribe((value) {
        capturedValue = value;
      });
      viewModel.setPassword('newpassword');
      expect(capturedValue, 'newpassword');
      dispose();
    });

    test('confirmPassword signal notifies listeners when changed', () {
      String? capturedValue;
      final dispose = viewModel.confirmPassword.subscribe((value) {
        capturedValue = value;
      });
      viewModel.setConfirmPassword('newpassword');
      expect(capturedValue, 'newpassword');
      dispose();
    });
  });
}
