import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/pages/signup_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/signup_view_model.dart';

import '../../../helpers/test_helpers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepo;
  late SignUpViewModel model;

  setUp(() {
    mockRepo = MockAuthRepository();
    model = SignUpViewModel(mockRepo);
  });

  tearDown(() {
    model.dispose();
  });

  group('SignUpPage', () {
    group('rendering', () {
      testWidgets('renders the auth shell with title and subtitle', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('UNI\u00b7STASH'), findsOneWidget);
        expect(find.text('Campus Bulletin Board'), findsOneWidget);
      });

      testWidgets('renders all form fields', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('DISPLAY NAME'), findsOneWidget);
        expect(find.text('SCHOOL EMAIL'), findsOneWidget);
        expect(find.text('PASSWORD'), findsOneWidget);
      });

      testWidgets('renders field placeholders', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('John Doe'), findsOneWidget);
        expect(find.text('you@university.edu'), findsOneWidget);
      });

      testWidgets('renders the SIGN UP button', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('SIGN UP'), findsOneWidget);
      });

      testWidgets('renders the login footer link', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Already have an account?'), findsOneWidget);
        expect(find.text('LOG IN'), findsOneWidget);
      });

      testWidgets('renders the campus verification card', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
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
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      });

      testWidgets('tapping toggle reveals password', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(LucideIcons.eyeOff));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.eye), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('shows error for empty display name', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your name'), findsOneWidget);
      });

      testWidgets('shows error for empty email', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter your email.'), findsOneWidget);
      });

      testWidgets('does not submit when validation fails', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('SIGN UP'));
        await tester.pumpAndSettle();

        expect(model.displayName.value, '');
        expect(model.email.value, '');
        expect(model.isLoading.value, false);
      });
    });

    group('loading state', () {
      testWidgets('model reflects loading state changes', (tester) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        expect(model.isLoading.value, false);
        model.isLoading.value = true;
        expect(model.isLoading.value, true);
        model.isLoading.value = false;
        expect(model.isLoading.value, false);
      });
    });

    group('lifecycle', () {
      testWidgets('does not dispose externally-provided ViewModel', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          buildTestApp(child: const SizedBox()),
        );
        await tester.pumpAndSettle();

        expect(model.displayName.value, '');
        model.setDisplayName('Test');
        expect(model.displayName.value, 'Test');
        model.dispose();
      });
    });

    group('error toast', () {
      testWidgets('shows a destructive toast when an error is set', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestApp(child: SignUpPage(viewModel: model)),
        );
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
