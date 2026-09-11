import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/chats/pages/chat_page.dart';
import 'package:uni_stash_mobile/features/listings/pages/home_page.dart';
import 'package:uni_stash_mobile/features/listings/pages/search_page.dart';
import 'package:uni_stash_mobile/features/listings/pages/sell_page.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
import 'package:uni_stash_mobile/features/profile/pages/profile_page.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// ProfilePage fetches through ProfileRepository on open; the shell tests
/// don't care about profile data, so a canned success is enough.
class _StubProfileRepository implements ProfileRepository {
  const _StubProfileRepository();

  @override
  Future<Result<User>> getProfile() async => const Result.success(
    User(
      id: 'test-uuid-123',
      email: 'test@example.com',
      displayName: 'Test User',
      emailVerified: true,
      role: 'student',
    ),
  );
}

void main() {
  late GoRouter router;

  setUp(() {
    // ProfilePage pushes its own GetIt scope; this parent scope supplies the
    // repository it resolves.
    di.pushNewScope(
      scopeName: 'mainShellTest',
      init: (getIt) {
        getIt.registerSingleton<ProfileRepository>(
          const _StubProfileRepository(),
        );
      },
    );

    router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const HomePage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/sell', builder: (_, _) => const SellPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/chat', builder: (_, _) => const ChatPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => const ProfilePage(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    // Let any in-flight page-scope pop (ProfilePage's dispose) land first,
    // then clean up defensively.
    await Future<void>.delayed(Duration.zero);
    while (di.currentScopeName != 'mainShellTest') {
      try {
        await di.popScope();
      } on Object {
        break;
      }
    }
    try {
      await di.popScope();
    } on Object {
      // Already at the base scope.
    }
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadTheme(
        data: usLightTheme,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MainShell', () {
    testWidgets('shows the home branch and the bottom nav bar initially', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(UsBottomNavBar), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
    });

    testWidgets('switches branches when a destination is tapped', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePage), findsOneWidget);
      // The nav bar label plus the page header title.
      expect(find.text('PROFILE'), findsNWidgets(2));

      await tester.tap(find.text('SEARCH'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
    });

    testWidgets('keeps the previous branch alive when switching tabs', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('CHAT'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);

      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(ChatPage), findsNothing);
    });

    testWidgets('highlights the selected destination in the nav bar', (
      tester,
    ) async {
      await pumpShell(tester);

      Finder inNavBar(String label) => find.descendant(
        of: find.byType(UsBottomNavBar),
        matching: find.text(label),
      );

      final theme = ShadTheme.of(tester.element(inNavBar('HOME')));
      var label = tester.widget<Text>(inNavBar('HOME'));
      expect(label.style?.color, theme.colorScheme.primary);

      await tester.tap(find.text('SELL'));
      await tester.pumpAndSettle();

      label = tester.widget<Text>(inNavBar('SELL'));
      expect(label.style?.color, theme.colorScheme.primary);
      final homeLabel = tester.widget<Text>(inNavBar('HOME'));
      expect(homeLabel.style?.color, theme.colorScheme.mutedForeground);
    });
  });
}
