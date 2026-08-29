import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/router/us_routes.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

// ---------------------------------------------------------------------------
// MOCK CLASSES
// ---------------------------------------------------------------------------
class MockAuthRepository extends Mock implements IAuthRepository {}

class MockLogger extends Mock implements Logger {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------
LoginResponse makeLoginResponse() {
  return const LoginResponse(
    accessToken: 'access_token_123',
    refreshToken: 'refresh_token_123',
    expiresIn: 900,
    user: User(
      id: 'uuid-123',
      email: 'test@example.com',
      displayName: 'Test User',
      emailVerified: true,
      role: 'student',
    ),
  );
}

/// Wraps [LoginPage] in MaterialApp.router with FTheme and GoRouter so that
/// forui widgets render correctly and navigation works.
Widget buildLoginPage() {
  return MaterialApp.router(
    builder: (context, child) => FTheme(
      data: FTheme.neutral.light.touch,
      child: child!,
    ),
    routerConfig: GoRouter(
      initialLocation: UsRoutes.login,
      routes: [
        GoRoute(
          path: UsRoutes.login,
          builder: (_, _) => const LoginPage(),
        ),
        GoRoute(
          path: UsRoutes.forgotPw,
          builder: (_, _) => const Scaffold(body: Text('Forgot Password Page')),
        ),
      ],
    ),
  );
}

/// Finds the underlying [EditableText] inside forui text form fields.
/// Forui's FTextFormField wraps a standard TextField, which contains an
/// EditableText.
Finder findTextFieldAt(int index) {
  final editables = find.byType(EditableText);
  return editables.at(index);
}

// ---------------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------------
void main() {
  late MockAuthRepository mockRepository;
  late MockLogger mockLogger;
  late MockFlutterSecureStorage mockStorage;
  late AuthViewModel authViewModel;

  final testDi = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(const LoginRequest(email: '', password: ''));
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    mockLogger = MockLogger();
    mockStorage = MockFlutterSecureStorage();

    // Stub secure storage writes so AuthViewModel.authenticate() doesn't fail.
    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});

    // Create a real AuthViewModel with mocked dependencies and register in DI.
    authViewModel = AuthViewModel(mockRepository, mockStorage);
    testDi.registerSingleton<IAuthRepository>(mockRepository);
    testDi.registerSingleton<Logger>(mockLogger);
    testDi.registerSingleton<FlutterSecureStorage>(mockStorage);
    testDi.registerSingleton<AuthViewModel>(authViewModel);
  });

  tearDown(testDi.reset);

  // =========================================================================
  // GROUP: Initial Render
  // =========================================================================
  group('Initial Render', () {
    testWidgets('renders form with email and password fields', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // FTextFormField wraps a TextField internally — find EditableText
      // which is the actual input widget inside each TextField.
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('renders Login header', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
    });
  });

  // =========================================================================
  // GROUP: Form Validation
  // =========================================================================
  group('Form Validation', () {
    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // Tap Sign In without entering anything.
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email.'), findsOneWidget);
    });

    testWidgets('shows error for invalid email format', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // Enter invalid email in the first text field.
      await tester.enterText(findTextFieldAt(0), 'invalid-email');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email.'), findsOneWidget);
    });

    testWidgets('shows error when password is empty', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // Enter valid email but leave password empty.
      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your password.'), findsOneWidget);
    });

    testWidgets('no validation errors for valid inputs', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // Stub repository so form submission succeeds.
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => Result.success(makeLoginResponse()),
      );

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'password123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email.'), findsNothing);
      expect(find.text('Please enter a valid email.'), findsNothing);
      expect(find.text('Please enter your password.'), findsNothing);
    });
  });

  // =========================================================================
  // GROUP: Login Submission
  // =========================================================================
  group('Login Submission', () {
    testWidgets('calls repository.login with correct credentials', (
      tester,
    ) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => Result.success(makeLoginResponse()),
      );

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'password123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.login(any())).called(1);
    });

    testWidgets('shows loading indicator during submission', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // Mock with a delay so we can observe loading state.
      when(() => mockRepository.login(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return Result.success(makeLoginResponse());
      });

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'password123');

      // Tap Sign In but only pump ONE frame to see intermediate loading state.
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      // The button should show an FCircularProgress (forui's spinner).
      expect(find.byType(FCircularProgress), findsOneWidget);

      // Wait for everything to finish.
      await tester.pumpAndSettle();
    });
  });

  // =========================================================================
  // GROUP: Error Display
  // =========================================================================
  group('Error Display', () {
    testWidgets('displays error message when login fails', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('Invalid credentials'),
      );

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'wrongpassword');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('displays network error message', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('No internet connection.'),
      );

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'password123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection.'), findsOneWidget);
    });

    testWidgets('clears previous error on successful retry', (tester) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      // First submit: failure.
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => const Result.failure('First error'),
      );

      await tester.enterText(findTextFieldAt(0), 'test@example.com');
      await tester.enterText(findTextFieldAt(1), 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('First error'), findsOneWidget);

      // Second submit: success.
      when(() => mockRepository.login(any())).thenAnswer(
        (_) async => Result.success(makeLoginResponse()),
      );

      await tester.enterText(findTextFieldAt(1), 'correct');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('First error'), findsNothing);
    });
  });

  // =========================================================================
  // GROUP: Forgot Password Link
  // =========================================================================
  group('Forgot Password', () {
    testWidgets('tapping Forgot password navigates to forgot-password route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLoginPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      // Verify we navigated to the forgot-password page.
      expect(find.text('Forgot Password Page'), findsOneWidget);
    });
  });
}
