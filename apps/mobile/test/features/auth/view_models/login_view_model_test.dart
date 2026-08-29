// =============================================================================
// FILE: login_view_model_test.dart
// PURPOSE: Unit tests for LoginViewModel — the business logic behind login
// WHAT YOU'LL LEARN: Testing signals, mocking dependencies, async state changes
// =============================================================================
//
// HOW TO USE THIS FILE:
// This file contains pseudo-code with detailed comments. Each test is outlined
// step-by-step so you can implement it yourself. Look for lines starting with
// "// => YOUR CODE:" — those are the lines you need to write.
//
// PATTERN: Every test follows Arrange → Act → Assert (AAA)
//   - ARRANGE: Set up mocks, variables, and initial state
//   - ACT: Perform the action you're testing
//   - ASSERT: Verify the result matches expectations
//
// =============================================================================

// ---------------------------------------------------------------------------
// SECTION 1: IMPORTS
// ---------------------------------------------------------------------------
// You need imports for:
// - flutter_test: The core testing framework (provides test(), group(), expect())
// - mocktail: For creating mock objects (your project already uses this)
// - signals_flutter: To read signal values (.value) and subscribe to changes
// - LoginViewModel: The class you're testing
// - IAuthRepository: The dependency that LoginViewModel uses (we'll mock it)
// - LoginRequest, LoginResponse, User: The data types used in the login flow
// - Result: Your custom success/failure type

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';

// ---------------------------------------------------------------------------
// SECTION 2: MOCK CLASSES
// ---------------------------------------------------------------------------
// Mocktail creates a fake version of IAuthRepository that we fully control.
// Instead of making real API calls, we decide what it returns.
//
// WHY: We want to test LoginViewModel in isolation — not the network layer.
// The real IAuthRepository talks to Dio/HTTP. Our mock just returns what we tell it.

class MockAuthRepository extends Mock implements IAuthRepository {}

// ---------------------------------------------------------------------------
// SECTION 3: HELPER FUNCTIONS
// ---------------------------------------------------------------------------
// These create test data so each test doesn't have to build everything
// from scratch.You can customize parameters when needed
// (e.g., makeLoginResponse(accessToken: 'xxx'))

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

// ---------------------------------------------------------------------------
// SECTION 4: MAIN TEST FUNCTION
// ---------------------------------------------------------------------------
// All tests live inside main(). The structure is:
//   main() {
//     setUp(() { ... });     // Runs BEFORE each test
//     tearDown(() { ... });  // Runs AFTER each test
//     group('...', () {      // Groups related tests together
//       test('...', () { ... });  // Individual test
//     });
//   }

void main() {
  // --------------------------------------------------------------------------
  // SECTION 4.1: SETUP & TEARDOWN
  // --------------------------------------------------------------------------
  // Declare variables here so they're accessible in all tests below.
  // "late" means "I'll assign this later, in setUp()".
  // "MockAuthRepository" is our fake — each test gets a fresh one.

  late MockAuthRepository mockRepository;
  late LoginViewModel viewModel;

  // setUp() runs BEFORE EVERY test — this ensures test isolation.
  // If test A changes the repository, test B still starts fresh.
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

  // tearDown() runs AFTER EVERY test — cleans up to prevent memory leaks.
  // LoginViewModel has dispose() that cleans up signals.
  tearDown(() {
    viewModel.dispose();
  });

  // --------------------------------------------------------------------------
  // SECTION 4.2: TEST GROUP — Initial State
  // --------------------------------------------------------------------------
  // These tests verify the ViewModel starts with correct default values.
  // When you create a LoginViewModel, all signals should have sensible defaults.

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

  // --------------------------------------------------------------------------
  // SECTION 4.3: TEST GROUP — setEmail and setPassword
  // --------------------------------------------------------------------------
  // These test the setter methods that the form calls when user types.

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

  // --------------------------------------------------------------------------
  // SECTION 4.4: submit() Success Cases
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // SECTION 4.5: submit() Failure Cases
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // SECTION 4.6: submit() Clears Previous State
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // SECTION 4.7: reset()
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // SECTION 4.8: Signal Reactivity
  // --------------------------------------------------------------------------
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
