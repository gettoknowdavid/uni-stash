import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
import 'package:uni_stash_mobile/features/auth/pages/reset_password_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/reset_password_view_model.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockAuthRepository mockRepo;
  late MockFlutterSecureStorage mockStorage;

  setUpAll(() {
    registerFallbackValue(
      const ResetPasswordRequest(code: '123456', newPassword: 'newpassword123'),
    );
    registerFallbackValue(
      const ForgotPasswordRequest(email: ''),
    );
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    mockStorage = MockFlutterSecureStorage();

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
    while (di.currentScopeName != 'test') {
      await di.popScope();
    }
    await di.popScope();
  });

  /// Pumps the page directly (no router) and returns its page-scoped VM.
  Future<ResetPasswordViewModel> pumpResetPasswordPage(
    WidgetTester tester, {
    String email = 'david.michael@stu.cu.edu.ng',
  }) async {
    await tester.pumpWidget(
      buildTestApp(child: ResetPasswordPage(email: email)),
    );
    await tester.pumpAndSettle();
    return di<ResetPasswordViewModel>();
  }

  /// Pumps the page inside a minimal GoRouter so the success effect can
  /// navigate to the login route.
  Future<void> pumpWithRouter(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/reset-password',
      routes: [
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => const ResetPasswordPage(
            email: 'david.michael@stu.cu.edu.ng',
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('LOGIN PAGE')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ShadTheme(
        data: usLightTheme,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => ShadToaster(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    final model = di<ResetPasswordViewModel>();
    model.setCode('123456');
    await tester.enterText(
      find.byType(ShadInputFormField).at(0),
      'newpassword123',
    );
    await tester.enterText(
      find.byType(ShadInputFormField).at(1),
      'newpassword123',
    );
    await tester.pump();
  }

  group('ResetPasswordPage', () {
    group('rendering', () {
      testWidgets('renders the title and the email description', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        expect(find.text('RESET PASSWORD'), findsOneWidget);
        expect(
          find.textContaining('david.michael@stu.cu.edu.ng'),
          findsOneWidget,
        );
      });

      testWidgets('renders a generic description when no email is given', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester, email: '');

        expect(
          find.textContaining('6-digit code from your email'),
          findsOneWidget,
        );
      });

      testWidgets('renders the OTP input and both password fields', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        expect(find.text('RECOVERY CODE'), findsOneWidget);
        expect(find.text('NEW PASSWORD'), findsOneWidget);
        expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
        expect(find.byType(ShadInputOTPSlot), findsNWidgets(6));
      });

      testWidgets('renders the SET NEW PASSWORD and Resend Code buttons', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        expect(find.text('SET NEW PASSWORD'), findsOneWidget);
        expect(find.text('Resend Code'), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('requires the complete code before submitting', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter the complete 6-digit code.'),
          findsOneWidget,
        );
        verifyNever(() => mockRepo.resetPassword(any()));
      });

      testWidgets('requires both passwords when the code is complete', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        di<ResetPasswordViewModel>().setCode('123456');
        await tester.pump();

        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter a new password.'), findsOneWidget);
        expect(find.text('Please confirm your password.'), findsOneWidget);
        verifyNever(() => mockRepo.resetPassword(any()));
      });

      testWidgets('rejects a password shorter than 10 characters', (
        tester,
      ) async {
        await pumpResetPasswordPage(tester);

        final model = di<ResetPasswordViewModel>();
        model.setCode('123456');
        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'short',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'short',
        );
        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        expect(
          find.text('Password must be at least 10 characters.'),
          findsOneWidget,
        );
        verifyNever(() => mockRepo.resetPassword(any()));
      });

      testWidgets('rejects mismatching confirmation', (tester) async {
        await pumpResetPasswordPage(tester);

        final model = di<ResetPasswordViewModel>();
        model.setCode('123456');
        await tester.enterText(
          find.byType(ShadInputFormField).at(0),
          'newpassword123',
        );
        await tester.enterText(
          find.byType(ShadInputFormField).at(1),
          'different456',
        );
        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        expect(find.text('Passwords do not match.'), findsOneWidget);
        verifyNever(() => mockRepo.resetPassword(any()));
      });
    });

    group('submit', () {
      testWidgets('resets the password and returns to login on success', (
        tester,
      ) async {
        when(() => mockRepo.resetPassword(any())).thenAnswer(
          (_) async => const Result.success(null),
        );

        await pumpWithRouter(tester);
        await fillValidForm(tester);

        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.resetPassword(
            const ResetPasswordRequest(
              code: '123456',
              newPassword: 'newpassword123',
            ),
          ),
        ).called(1);
        expect(find.text('Password Reset'), findsOneWidget);

        // Navigated to the login screen after a successful reset.
        expect(find.text('LOGIN PAGE'), findsOneWidget);
        expect(find.text('SET NEW PASSWORD'), findsNothing);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });

      testWidgets('shows a destructive toast when the code is rejected', (
        tester,
      ) async {
        when(() => mockRepo.resetPassword(any())).thenAnswer(
          (_) async => const Result.failure('Invalid or expired code'),
        );

        await pumpResetPasswordPage(tester);
        await fillValidForm(tester);

        await tester.tap(find.text('SET NEW PASSWORD'));
        await tester.pumpAndSettle();

        expect(find.text('Authentication Error'), findsOneWidget);
        expect(find.text('Invalid or expired code'), findsOneWidget);
        expect(find.text('SET NEW PASSWORD'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('resend', () {
      testWidgets('resends the recovery code and confirms via a toast', (
        tester,
      ) async {
        when(() => mockRepo.forgotPassword(any())).thenAnswer(
          (_) async => const Result.success(null),
        );

        await pumpResetPasswordPage(tester);

        await tester.tap(find.text('Resend Code'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        verify(
          () => mockRepo.forgotPassword(
            const ForgotPasswordRequest(
              email: 'david.michael@stu.cu.edu.ng',
            ),
          ),
        ).called(1);
        expect(find.text('Code Sent'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('lifecycle', () {
      testWidgets('disposes the page-scoped ViewModel when removed', (
        tester,
      ) async {
        final model = await pumpResetPasswordPage(tester);

        await tester.pumpWidget(buildTestApp(child: const SizedBox()));
        await tester.pumpAndSettle();

        expect(model.code.disposed, isTrue);
        expect(model.newPassword.disposed, isTrue);
        expect(model.confirmPassword.disposed, isTrue);
      });
    });
  });
}
