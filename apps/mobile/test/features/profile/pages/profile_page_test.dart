import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
import 'package:uni_stash_mobile/features/profile/pages/profile_page.dart';
import 'package:uni_stash_mobile/features/profile/view_models/profile_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

import '../../../helpers/test_helpers.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

User makeUser({
  String displayName = 'Adaeze Bakare',
  bool emailVerified = true,
}) {
  return User(
    id: 'user-1',
    email: 'adaeze@uniport.edu.ng',
    displayName: displayName,
    emailVerified: emailVerified,
    role: 'student',
  );
}

void main() {
  late MockProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockProfileRepository();

    // The page pushes its own scope and registers its view model there, so
    // this scope only supplies the mock it depends on. It is popped in
    // tearDown; the page scope is popped by the page itself on dispose.
    di.pushNewScope(
      scopeName: 'test',
      init: (getIt) {
        getIt.registerSingleton<ProfileRepository>(mockRepo);
      },
    );

    when(() => mockRepo.getProfile()).thenAnswer(
      (_) async => Result.success(makeUser()),
    );
  });

  tearDown(() async {
    // A page being torn down pops its scope with an unawaited future, which
    // can still be in flight here; give it a turn to land first.
    await Future<void>.delayed(Duration.zero);
    // A failed test can also leave scopes behind; pop defensively down to
    // (and including) the test scope, absorbing any racing pops.
    while (di.currentScopeName != 'test') {
      try {
        await di.popScope();
      } on Object {
        break;
      }
    }
    try {
      await di.popScope();
    } on Object {
      // Already at the base scope — nothing left to clean up.
    }
  });

  /// Pumps the page and returns the page-scoped [ProfileViewModel] it
  /// created.
  Future<ProfileViewModel> pumpProfilePage(WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp(child: const ProfilePage()));
    await tester.pumpAndSettle();
    return di<ProfileViewModel>();
  }

  group('ProfilePage', () {
    group('rendering', () {
      testWidgets('renders the profile header and verified badge', (
        tester,
      ) async {
        await pumpProfilePage(tester);

        expect(find.text('PROFILE'), findsOneWidget);
        expect(find.text('VERIFIED'), findsOneWidget);
        expect(find.text('ADAEZE B.'), findsOneWidget);
        expect(find.text('@UNIPORT.EDU.NG'), findsOneWidget);
        expect(find.text('STUDENT STATUS CONFIRMED'), findsOneWidget);
      });

      testWidgets('hides the verified chrome for an unverified user', (
        tester,
      ) async {
        when(() => mockRepo.getProfile()).thenAnswer(
          (_) async => Result.success(makeUser(emailVerified: false)),
        );

        await pumpProfilePage(tester);

        expect(find.text('VERIFIED'), findsNothing);
        expect(find.text('STUDENT STATUS CONFIRMED'), findsNothing);
        // Name and email tag still render.
        expect(find.text('ADAEZE B.'), findsOneWidget);
      });

      testWidgets('renders the EDIT PROFILE button', (tester) async {
        await pumpProfilePage(tester);

        expect(find.text('EDIT PROFILE'), findsOneWidget);
      });

      testWidgets('renders the stats strip with the view model values', (
        tester,
      ) async {
        await pumpProfilePage(tester);

        expect(find.text('12'), findsOneWidget);
        expect(find.text('45'), findsOneWidget);
        expect(find.text('8'), findsOneWidget);
        expect(find.text('ACTIVE LISTINGS'), findsOneWidget);
        expect(find.text('ITEMS SOLD'), findsOneWidget);
        expect(find.text('SAVED'), findsOneWidget);
      });

      testWidgets('renders all four menu rows', (tester) async {
        await pumpProfilePage(tester);

        expect(find.text('MY LISTINGS'), findsOneWidget);
        expect(find.text('SAVED ITEMS'), findsOneWidget);
        expect(find.text('TRANSACTION HISTORY'), findsOneWidget);
        expect(find.text('SUPPORT'), findsOneWidget);
      });

      testWidgets('shows a spinner while the profile is loading', (
        tester,
      ) async {
        final completer = Completer<Result<User>>();
        when(() => mockRepo.getProfile()).thenAnswer((_) => completer.future);

        // Deliberately not settling: the fetch future never completes.
        await tester.pumpWidget(buildTestApp(child: const ProfilePage()));
        await tester.pump();

        expect(find.byType(ShadSpinner), findsOneWidget);
        expect(find.text('ADAEZE B.'), findsNothing);

        // Unblock the pending fetch so dispose doesn't trip over it.
        completer.complete(Result.success(makeUser()));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    });

    group('data loading', () {
      testWidgets('fetches the profile on page open', (tester) async {
        await pumpProfilePage(tester);

        verify(() => mockRepo.getProfile()).called(1);
      });

      testWidgets('shows an error view with retry on failure', (tester) async {
        when(() => mockRepo.getProfile()).thenAnswer(
          (_) async => const Result.failure('No internet connection.'),
        );

        await pumpProfilePage(tester);

        expect(find.text('No internet connection.'), findsOneWidget);
        expect(find.text('RETRY'), findsOneWidget);

        // Retry succeeds → the content renders.
        when(() => mockRepo.getProfile()).thenAnswer(
          (_) async => Result.success(makeUser()),
        );
        await tester.tap(find.text('RETRY'));
        await tester.pumpAndSettle();

        expect(find.text('ADAEZE B.'), findsOneWidget);
      });

      testWidgets('disposes the page-scoped ViewModel when removed', (
        tester,
      ) async {
        final model = await pumpProfilePage(tester);

        // Remove the widget — the page pops its GetIt scope on dispose, which
        // disposes the view model it created.
        await tester.pumpWidget(buildTestApp(child: const SizedBox()));
        await tester.pumpAndSettle();

        expect(model.profile.disposed, isTrue);
        expect(model.stats.disposed, isTrue);
      });
    });

    group('interactions', () {
      testWidgets('tapping a menu row shows a coming-soon toast', (
        tester,
      ) async {
        await pumpProfilePage(tester);

        await tester.ensureVisible(find.text('MY LISTINGS'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('MY LISTINGS'));
        await tester.pumpAndSettle();

        expect(find.text('Coming Soon'), findsOneWidget);
        expect(find.text('MY LISTINGS is on the way.'), findsOneWidget);

        // Let the toast's default 5s display timer elapse before the test
        // ends.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });

      testWidgets('tapping EDIT PROFILE shows a coming-soon toast', (
        tester,
      ) async {
        await pumpProfilePage(tester);

        await tester.ensureVisible(find.text('EDIT PROFILE'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('EDIT PROFILE'));
        await tester.pumpAndSettle();

        expect(find.text('Coming Soon'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });
  });
}
