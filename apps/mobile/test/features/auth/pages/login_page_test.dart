import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/login_view_model.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepo;
  late LoginViewModel model;

  setUp(() {
    mockRepo = MockAuthRepository();
    model = LoginViewModel(mockRepo);
  });

  tearDown(() {
    model.dispose();
  });

  group('LoginPage', () {
    group('rendering', () {
      testWidgets('renders the auth shell with title and subtitle',
          (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('UNI\u00b7STASH'), findsOneWidget);
        expect(find.text('Campus Bulletin Board'), findsOneWidget);
      });

      testWidgets('renders email field with correct label and placeholder',
          (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('SCHOOL EMAIL'), findsOneWidget);
        expect(find.text('you@university.edu'), findsOneWidget);
      });

      testWidgets('renders password field with correct label', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('PASSWORD'), findsOneWidget);
      });

      testWidgets('renders the LOG IN button', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('LOG IN'), findsOneWidget);
      });

      testWidgets('renders the sign-up footer link', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text("Don't have an account?"), findsOneWidget);
        expect(find.text('SIGN UP'), findsOneWidget);
      });
    });

    group('password visibility', () {
      testWidgets('password starts obscured with eye-off icon', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
        expect(find.byIcon(LucideIcons.eye), findsNothing);
      });

      testWidgets('tapping toggle reveals password', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eye), findsOneWidget);
        expect(find.byIcon(LucideIcons.eyeOff), findsNothing);
      });

      testWidgets('tapping toggle again hides password', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.eye));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('shows error for empty email and password', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your email.'), findsOneWidget);
        expect(find.text('Please enter your password.'), findsOneWidget);
      });

      testWidgets('does not submit when validation fails', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('LOG IN'));
        await tester.pumpAndSettle();

        expect(model.email.value, '');
        expect(model.password.value, '');
        expect(model.isLoading.value, false);
      });
    });

    group('loading state', () {
      testWidgets('model reflects loading state changes', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(model.isLoading.value, false);

        // Directly toggle loading on the model — the SignalWidget sub-widgets
        // would rebuild, but we just verify the model contract here.
        model.isLoading.value = true;
        expect(model.isLoading.value, true);

        model.isLoading.value = false;
        expect(model.isLoading.value, false);
      });
    });

    group('lifecycle', () {
      testWidgets('does not dispose externally-provided ViewModel',
          (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        // Remove the widget — the page should NOT dispose our model
        await tester.pumpWidget(
          buildTestApp(child: const SizedBox()),
        );
        await tester.pumpAndSettle();

        // Model should still be usable
        expect(model.email.value, '');
        model.setEmail('test@example.com');
        expect(model.email.value, 'test@example.com');
        model.dispose();
      });
    });

    group('error toast', () {
      testWidgets('shows a destructive toast when an error is set',
          (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: LoginPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

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
