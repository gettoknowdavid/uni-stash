import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

LoginResponse makeLoginResponse({
  String accessToken = 'test_access_token',
  String refreshToken = 'test_refresh_token',
  int expiresIn = 900,
  User? user,
}) {
  return LoginResponse(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresIn: expiresIn,
    user:
        user ??
        const User(
          id: 'test-uuid-123',
          email: 'test@example.com',
          displayName: 'Test User',
          emailVerified: true,
          role: 'student',
        ),
  );
}

void main() {
  late MockAuthRepository mockRepository;
  late LoginViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const LoginRequest(email: '', password: ''),
    );
    registerFallbackValue(
      const LoginResponse(
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        expiresIn: 900,
        user: User(
          id: 'test-uuid-123',
          email: 'test@example.com',
          displayName: 'Test User',
          emailVerified: true,
          role: 'student',
        ),
      ),
    );
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    viewModel = LoginViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('Initial State', () {
    test('email signal starts as empty string', () {
      final emailValue = viewModel.email.value;
      expect(emailValue, '');
    });

    test('password signal starts as empty string', () {
      final passwordValue = viewModel.password.value;
      expect(passwordValue, '');
    });

    test('isLoading signal starts as false', () {
      final isLoadingValue = viewModel.isLoading.value;
      expect(isLoadingValue, false);
    });

    test('error signal starts as null', () {
      final errorValue = viewModel.error.value;
      expect(errorValue, isNull);
    });

    test('result signal starts as null', () {
      final resultValue = viewModel.result.value;
      expect(resultValue, isNull);
    });
  });

  group('setEmail and setPassword', () {
    test('setEmail updates email signal', () {
      viewModel.setEmail('test@example.com');
      expect(viewModel.email.value, 'test@example.com');
    });

    test('setEmail with null sets empty string (null safety)', () {
      viewModel.setEmail('test@example.com');
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
  });

  group('submit - Success', () {
    test('successful login sets result signal and clears error', () async {
      final loginResponse = makeLoginResponse();
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => Result.success(loginResponse),
      );

      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.result.value, equals(loginResponse));
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);

      verify(() => mockRepository.login(any())).called(1);
    });

    test('isLoading goes true then false during submission', () async {
      when(() => mockRepository.login(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return Result.success(makeLoginResponse());
      });
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      expect(viewModel.isLoading.value, true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(viewModel.isLoading.value, false);
    });
  });

  group('submit - Failure', () {
    test('failed login sets error signal', () async {
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('Invalid credentials'),
      );
      viewModel.setEmail('wrong@example.com');
      viewModel.setPassword('wrongpassword');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, 'Invalid credentials');
      expect(viewModel.result.value, isNull);
    });

    test('network timeout sets timeout message', () async {
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure(
          'Connection timed out. Please check your network.',
        ),
      );
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, contains('timed out'));
    });

    test('server error sets server error message', () async {
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure(
          'Server error (500). Please try again later.',
        ),
      );
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, contains('Server error'));
    });
  });

  group('submit - Clears Previous State', () {
    test('submit clears previous error on success', () async {
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('First error'),
      );
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, 'First error');

      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => Result.success(makeLoginResponse()),
      );
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNotNull);
    });
  });

  group('reset', () {
    test('reset clears all signals to initial values', () {
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');

      viewModel.reset();
      expect(viewModel.email.value, '');
      expect(viewModel.password.value, '');
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
      expect(viewModel.result.value, isNull);
    });

    test('reset after failed login clears error', () async {
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('Error'),
      );
      viewModel.setEmail('test@example.com');
      viewModel.setPassword('password123');
      viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, 'Error');
      viewModel.reset();
      expect(viewModel.error.value, isNull);
    });
  });

  group('Signal Reactivity', () {
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
  });
}
