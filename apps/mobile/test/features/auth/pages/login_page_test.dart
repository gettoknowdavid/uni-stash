import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

LoginResponse makeLoginResponse() {
  return const LoginResponse(
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
  );
}

void main() {
  late MockAuthRepository mockRepo;
  late MockFlutterSecureStorage mockStorage;

  setUpAll(() {
    registerFallbackValue(const LoginRequest(email: '', password: ''));
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockFlutterSecureStorage();

    // The page pushes its own scope and registers its view model there, so
    // this scope only supplies the mocks it depends on. It is popped in
    // tearDown; the page scope is popped by the page itself on dispose.
    di.pushNewScope(
      scopeName: 'test',
      init: (getIt) {
        getIt.registerSingleton<IAuthRepository>(mockRepo);
        getIt.registerSingleton<FlutterSecureStorage>(mockStorage);
        getIt.registerLazySingleton<AuthViewModel>(
          () => AuthViewModel(
            getIt<IAuthRepository>(),
            getIt<FlutterSecureStorage>(),
          ),
        );
      },
    );

    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockStorage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    // Pop every scope above the test scope (e.g. a page scope left behind
    // after a failed test), then the test scope itself.
    while (di.currentScopeName != 'test') {
      await di.popScope();
    }
    await di.popScope();
  });

  /// Pumps the page and returns the page-scoped [LoginViewModel] it created.
  Future<LoginViewModel> pumpLoginPage(WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp(child: const LoginPage()));
    await tester.pumpAndSettle();
    return di<LoginViewModel>();
  }

  group('LoginPage', () {
    group('rendering', () {
      testWidgets('renders the auth shell with title and subtitle', (
        tester,
      ) async {
        await pumpLoginPage(tester);

        expect(find.text('UNI\u00b7STASH'), findsOneWidget);
        expect(find.text('Campus Bulletin Board'), findsOneWidget);
      });

      testWidgets('renders email field with correct label and placeholder', (
        tester,
      ) async {
        await pumpLoginPage(tester);

        expect(find.text('SCHOOL EMAIL'), findsOneWidget);
        expect(find.text('you@university.edu'), findsOneWidget);
      });

      testWidgets('renders password field with correct label', (tester) async {
        await pumpLoginPage(tester);

        expect(find.text('PASSWORD'), findsOneWidget);
      });

      testWidgets('renders the LOG IN button', (tester) async {
        await pumpLoginPage(tester);

        expect(find.text('LOG IN'), findsOneWidget);
      });

      testWidgets('renders the sign-up footer link', (tester) async {
        await pumpLoginPage(tester);

        expect(find.widgetWithText(ShadButton, 'SIGN UP'), findsOneWidget);
      });
    });

    group('password visibility', () {
      testWidgets('password starts obscured with eye-off icon', (tester) async {
        await pumpLoginPage(tester);

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
        expect(find.byIcon(LucideIcons.eye), findsNothing);
      });

      testWidgets('tapping toggle reveals password', (tester) async {
        await pumpLoginPage(tester);

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eye), findsOneWidget);
        expect(find.byIcon(LucideIcons.eyeOff), findsNothing);
      });

      testWidgets('tapping toggle again hides password', (tester) async {
        await pumpLoginPage(tester);

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.eye));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('shows error for empty email and password', (tester) async {
        await pumpLoginPage(tester);

        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your email.'), findsOneWidget);
        expect(find.text('Please enter your password.'), findsOneWidget);
      });

      testWidgets('does not submit when validation fails', (tester) async {
        final model = await pumpLoginPage(tester);

        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        expect(model.email.value, '');
        expect(model.password.value, '');
        expect(model.isLoading.value, false);
        verifyNever(() => mockRepo.login(any()));
      });
    });

    group('submit', () {
      testWidgets('submits credentials and authenticates on success', (
        tester,
      ) async {
        final response = makeLoginResponse();
        when(() => mockRepo.login(any())).thenAnswer(
          (_) async => Result.success(response),
        );

        final model = await pumpLoginPage(tester);

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'test@example.com',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'password123',
        );
        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.login(
            const LoginRequest(
              email: 'test@example.com',
              password: 'password123',
            ),
          ),
        ).called(1);

        // The page forwards the response to AuthViewModel and resets the form.
        expect(di<AuthViewModel>().status.value, AuthStatus.authenticated);
        expect(model.email.value, '');
        expect(model.isLoading.value, false);
      });

      testWidgets('shows a destructive toast when submission fails', (
        tester,
      ) async {
        when(() => mockRepo.login(any())).thenAnswer(
          (_) async => const Result.failure('Invalid credentials'),
        );

        await pumpLoginPage(tester);

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'test@example.com',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'password123',
        );
        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        expect(find.text('Authentication Error'), findsOneWidget);
        expect(find.text('Invalid credentials'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('loading state', () {
      testWidgets('shows a spinner and disables the button while submitting', (
        tester,
      ) async {
        final completer = Completer<Result<LoginResponse>>();
        when(() => mockRepo.login(any())).thenAnswer((_) => completer.future);

        final model = await pumpLoginPage(tester);

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'test@example.com',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'password123',
        );
        await tester.tap(find.text('LOG IN'));
        await tester.pump();

        expect(model.isLoading.value, true);
        expect(find.byType(ShadSpinner), findsOneWidget);
        expect(find.text('LOG IN'), findsNothing);

        completer.complete(Result.success(makeLoginResponse()));
        await tester.pumpAndSettle();

        expect(model.isLoading.value, false);
        expect(find.byType(ShadSpinner), findsNothing);
        expect(find.text('LOG IN'), findsOneWidget);
      });
    });

    group('lifecycle', () {
      testWidgets('disposes the page-scoped ViewModel when removed', (
        tester,
      ) async {
        final model = await pumpLoginPage(tester);

        // Remove the widget — the page pops its GetIt scope on dispose, which
        // disposes the view model it created.
        await tester.pumpWidget(buildTestApp(child: const SizedBox()));
        await tester.pumpAndSettle();

        expect(model.email.disposed, isTrue);
        expect(model.password.disposed, isTrue);
      });
    });

    group('error toast', () {
      testWidgets('shows a destructive toast when an error is set', (
        tester,
      ) async {
        final model = await pumpLoginPage(tester);

        model.error.value = 'Invalid credentials';

        // The page effect reacts on a microtask and defers showing the toast
        // to a post-frame callback, so pump a few times to let it surface.
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Authentication Error'), findsOneWidget);
        expect(find.text('Invalid credentials'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });
  });
}
