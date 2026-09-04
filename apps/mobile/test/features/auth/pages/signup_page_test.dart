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
import 'package:uni_stash_mobile/features/auth/pages/signup_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/signup_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

SignUpResponse makeSignUpResponse() {
  return const SignUpResponse(
    user: User(
      id: 'test-uuid-123',
      email: 'test@university.edu',
      displayName: 'Test User',
      emailVerified: false,
      role: 'student',
    ),
    accessToken: 'test_access_token',
    refreshToken: 'test_refresh_token',
    expiresIn: 900,
  );
}

void main() {
  late MockAuthRepository mockRepo;
  late MockFlutterSecureStorage mockStorage;
  late SignUpViewModel model;

  setUpAll(() {
    registerFallbackValue(
      const SignUpRequest(email: '', password: '', displayName: ''),
    );
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockFlutterSecureStorage();

    // The pages resolve their view models through GetIt, so tests register
    // mocks in a dedicated scope that is popped (and disposed) in tearDown.
    di.pushNewScope(
      init: (getIt) {
        getIt.registerSingleton<IAuthRepository>(mockRepo);
        getIt.registerSingleton<FlutterSecureStorage>(mockStorage);
        getIt.registerLazySingleton<AuthViewModel>(
          () => AuthViewModel(
            getIt<IAuthRepository>(),
            getIt<FlutterSecureStorage>(),
          ),
        );
        getIt.registerLazySingleton<SignUpViewModel>(
          () => SignUpViewModel(getIt<IAuthRepository>()),
        );
      },
    );
    model = di<SignUpViewModel>();

    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockStorage.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    // Pops the scope, which disposes the registered Disposable view models.
    await di.popScope();
  });

  group('SignUpPage', () {
    group('rendering', () {
      testWidgets('renders the auth shell with title and subtitle', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('UNI\u00b7STASH'), findsOneWidget);
        expect(find.text('Campus Bulletin Board'), findsOneWidget);
      });

      testWidgets('renders all form fields', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('DISPLAY NAME'), findsOneWidget);
        expect(find.text('SCHOOL EMAIL'), findsOneWidget);
        expect(find.text('PASSWORD'), findsOneWidget);
      });

      testWidgets('renders field placeholders', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('John Doe'), findsOneWidget);
        expect(find.text('you@university.edu'), findsOneWidget);
      });

      testWidgets('renders the SIGN UP button', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('SIGN UP'), findsOneWidget);
      });

      testWidgets('renders the login footer link', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('Already have an account?'), findsOneWidget);
        expect(find.text('LOG IN'), findsOneWidget);
      });

      testWidgets('renders the campus verification card', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.text('CAMPUS VERIFICATION'), findsOneWidget);
        expect(
          find.textContaining('We verify all new members'),
          findsOneWidget,
        );
      });
    });

    group('password visibility', () {
      testWidgets('password starts obscured', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      });

      testWidgets('tapping toggle reveals password', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eye), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('shows error for empty display name', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your name'), findsOneWidget);
      });

      testWidgets('shows error for empty email', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your email.'), findsOneWidget);
      });

      testWidgets('shows error for password shorter than 8 characters', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'Jane Doe',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'jane@university.edu',
        );
        await tester.enterText(find.byType(ShadInputFormField).at(2), 'short');
        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(
          find.text('Password must be at least 8 characters.'),
          findsOneWidget,
        );
      });

      testWidgets('does not submit when validation fails', (tester) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(model.displayName.value, '');
        expect(model.email.value, '');
        expect(model.isLoading.value, false);
        verifyNever(() => mockRepo.signUp(any()));
      });
    });

    group('submit', () {
      testWidgets('submits the form and authenticates on success', (
        tester,
      ) async {
        final response = makeSignUpResponse();
        when(() => mockRepo.signUp(any())).thenAnswer(
          (_) async => Result.success(response),
        );

        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'Jane Doe',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'jane@university.edu',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(2),
          'password123',
        );
        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.signUp(
            const SignUpRequest(
              email: 'jane@university.edu',
              password: 'password123',
              displayName: 'Jane Doe',
            ),
          ),
        ).called(1);

        // The page forwards the response to AuthViewModel and resets the form.
        expect(di<AuthViewModel>().status.value, AuthStatus.authenticated);
        expect(model.displayName.value, '');
        expect(model.isLoading.value, false);
      });

      testWidgets('shows a destructive toast when submission fails', (
        tester,
      ) async {
        when(() => mockRepo.signUp(any())).thenAnswer(
          (_) async => const Result.failure('Account already exists'),
        );

        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'Jane Doe',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'jane@university.edu',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(2),
          'password123',
        );
        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(find.text('Authentication Error'), findsOneWidget);
        expect(find.text('Account already exists'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('loading state', () {
      testWidgets('shows a spinner and disables the button while submitting', (
        tester,
      ) async {
        final completer = Completer<Result<SignUpResponse>>();
        when(() => mockRepo.signUp(any())).thenAnswer((_) => completer.future);

        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'Jane Doe',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'jane@university.edu',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(2),
          'password123',
        );
        await tester.tap(find.text('SIGN UP'));
        await tester.pump();

        expect(model.isLoading.value, true);
        expect(find.byType(ShadSpinner), findsOneWidget);
        expect(find.text('SIGN UP'), findsNothing);

        completer.complete(Result.success(makeSignUpResponse()));
        await tester.pumpAndSettle();

        expect(model.isLoading.value, false);
        expect(find.byType(ShadSpinner), findsNothing);
        expect(find.text('SIGN UP'), findsOneWidget);
      });
    });

    group('lifecycle', () {
      testWidgets('does not dispose the DI-provided ViewModel when removed', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        // Remove the widget — the page must NOT dispose the model; GetIt owns
        // its lifecycle and disposes it when the test scope is popped.
        await tester.pumpWidget(buildTestApp(child: const SizedBox()));
        await tester.pumpAndSettle();

        expect(model.displayName.value, '');
        model.setDisplayName('Test');
        expect(model.displayName.value, 'Test');
      });
    });

    group('error toast', () {
      testWidgets('shows a destructive toast when an error is set', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestApp(child: const SignUpPage()));
        await tester.pumpAndSettle();

        model.error.value = 'Account already exists';

        // The page effect reacts on a microtask and defers showing the toast
        // to a post-frame callback, so pump a few times to let it surface.
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Authentication Error'), findsOneWidget);
        expect(find.text('Account already exists'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });
  });
}
