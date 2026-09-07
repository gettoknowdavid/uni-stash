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
import 'package:uni_stash_mobile/features/auth/pages/verify_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/auth/view_models/verify_otp_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

VerifyOtpResponse makeVerifyOtpResponse() {
  return const VerifyOtpResponse(
    verified: true,
    accessToken: 'test_access_token',
    refreshToken: 'test_refresh_token',
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
  late MockAuthRepository mockRepo;
  late MockFlutterSecureStorage mockStorage;

  setUpAll(() {
    registerFallbackValue(
      const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
    );
    registerFallbackValue(
      const ResendVerificationRequest(email: 'test@university.edu'),
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

  /// Pumps the page and returns the page-scoped [VerifyOtpViewModel].
  Future<VerifyOtpViewModel> pumpVerifyPage(
    WidgetTester tester, {
    String? email = 'test@university.edu',
  }) async {
    await tester.pumpWidget(
      buildTestApp(child: VerifyPage(email: email)),
    );
    await tester.pumpAndSettle();
    return di<VerifyOtpViewModel>();
  }

  group('VerifyPage', () {
    group('rendering', () {
      testWidgets('renders the page title and the code description', (
        tester,
      ) async {
        await pumpVerifyPage(tester);

        expect(find.text('VERIFY EMAIL'), findsOneWidget);
        expect(find.textContaining('test@university.edu'), findsOneWidget);
      });

      testWidgets('renders a generic description without an email', (
        tester,
      ) async {
        await pumpVerifyPage(tester, email: null);

        expect(find.textContaining('code sent to your email'), findsOneWidget);
      });

      testWidgets('renders the VERIFY and Resend Code buttons', (tester) async {
        await pumpVerifyPage(tester);

        expect(find.text('VERIFY'), findsOneWidget);
        expect(find.text('Resend Code'), findsOneWidget);
      });

      testWidgets('renders six OTP slots', (tester) async {
        await pumpVerifyPage(tester);

        // The input is split into two groups of three slots.
        expect(find.byType(ShadInputOTPGroup), findsNWidgets(2));
        expect(find.byType(ShadInputOTPSlot), findsNWidgets(6));
      });
    });

    group('validation', () {
      testWidgets('requires the complete 6-digit code before submitting', (
        tester,
      ) async {
        await pumpVerifyPage(tester);

        await tester.tap(find.text('VERIFY'));
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter the complete 6-digit code.'),
          findsOneWidget,
        );
        verifyNever(() => mockRepo.verifyOtp(any()));
      });

      testWidgets('clears the code error once the user starts typing', (
        tester,
      ) async {
        final model = await pumpVerifyPage(tester);

        await tester.tap(find.text('VERIFY'));
        await tester.pumpAndSettle();
        expect(
          find.text('Please enter the complete 6-digit code.'),
          findsOneWidget,
        );

        // Typing into the first OTP slot routes through onChanged and clears
        // the stale error.
        await tester.enterText(find.byType(ShadInput).first, '1');
        await tester.pump();

        expect(model.code.value, '1');
        expect(
          find.text('Please enter the complete 6-digit code.'),
          findsNothing,
        );
      });
    });

    group('submit', () {
      testWidgets('verifies the code and signs the user in on success', (
        tester,
      ) async {
        when(() => mockRepo.verifyOtp(any())).thenAnswer(
          (_) async => Result.success(makeVerifyOtpResponse()),
        );

        final model = await pumpVerifyPage(tester);
        await tester.enterText(find.byType(ShadInput).first, '123456');
        await tester.pump();
        expect(model.code.value, '123456');

        await tester.tap(find.text('VERIFY'));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.verifyOtp(
            const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
          ),
        ).called(1);

        expect(di<AuthViewModel>().status.value, AuthStatus.authenticated);
        expect(di<AuthViewModel>().verified.value, isTrue);
        expect(model.isLoading.value, isFalse);
      });

      testWidgets('shows a destructive toast when the code is rejected', (
        tester,
      ) async {
        when(() => mockRepo.verifyOtp(any())).thenAnswer(
          (_) async => const Result.failure('Invalid or expired code'),
        );

        final model = await pumpVerifyPage(tester);
        model.setCode('000000');

        await tester.tap(find.text('VERIFY'));
        await tester.pumpAndSettle();

        expect(find.text('Verification Error'), findsOneWidget);
        expect(find.text('Invalid or expired code'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('resend', () {
      testWidgets('resends the code and confirms via a toast', (tester) async {
        when(() => mockRepo.resendVerification(any())).thenAnswer(
          (_) async => const Result.success(null),
        );

        await pumpVerifyPage(tester);

        await tester.tap(find.text('Resend Code'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        verify(
          () => mockRepo.resendVerification(
            const ResendVerificationRequest(email: 'test@university.edu'),
          ),
        ).called(1);
        expect(find.text('Code Sent'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });

      testWidgets('shows an error toast when resending fails', (tester) async {
        when(() => mockRepo.resendVerification(any())).thenAnswer(
          (_) async => const Result.failure('Email is already verified'),
        );

        await pumpVerifyPage(tester);

        await tester.tap(find.text('Resend Code'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Verification Error'), findsOneWidget);
        expect(find.text('Email is already verified'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    group('loading state', () {
      testWidgets('shows a spinner and disables the button while verifying', (
        tester,
      ) async {
        final completer = Completer<Result<VerifyOtpResponse>>();
        when(() => mockRepo.verifyOtp(any())).thenAnswer(
          (_) => completer.future,
        );

        final model = await pumpVerifyPage(tester);
        model.setCode('123456');

        await tester.tap(find.text('VERIFY'));
        await tester.pump();

        expect(model.isLoading.value, isTrue);
        expect(find.byType(ShadSpinner), findsOneWidget);
        expect(find.text('VERIFY'), findsNothing);

        completer.complete(Result.success(makeVerifyOtpResponse()));
        await tester.pumpAndSettle();

        expect(model.isLoading.value, isFalse);
        expect(find.byType(ShadSpinner), findsNothing);
      });
    });

    group('lifecycle', () {
      testWidgets('disposes the page-scoped ViewModel when removed', (
        tester,
      ) async {
        final model = await pumpVerifyPage(tester);

        await tester.pumpWidget(buildTestApp(child: const SizedBox()));
        await tester.pumpAndSettle();

        expect(model.code.disposed, isTrue);
        expect(model.error.disposed, isTrue);
      });
    });
  });
}
