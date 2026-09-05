import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/features/listings/pages/home_page.dart';
import 'package:uni_stash_mobile/features/profile/pages/profile_page.dart';
import 'package:uni_stash_mobile/router/us_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  const credentials = UserCredentials(
    user: User(
      id: 'test-uuid-123',
      email: 'test@example.com',
      displayName: 'Test User',
      emailVerified: true,
      role: 'student',
    ),
    accessToken: 'test_access_token',
    refreshToken: 'test_refresh_token',
    expiresIn: 900,
  );

  setUpAll(() {
    final mockRepo = MockAuthRepository();
    final mockStorage = MockFlutterSecureStorage();

    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockStorage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});

    // One AuthViewModel for the whole file: the router's refreshListenable
    // subscribes to its status signal on first use, so reusing the instance
    // keeps the redirect listener alive across tests.
    di.pushNewScope(
      scopeName: 'routerTest',
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
  });

  setUp(() {
    // Reset to a clean, unauthenticated state for every test.
    di<AuthViewModel>().unauthenticate();
  });

  tearDownAll(() async {
    // Pop any page scope left behind (e.g. LoginPage), then the test scope.
    while (di.currentScopeName != 'routerTest') {
      await di.popScope();
    }
    await di.popScope();
  });

  Future<void> pumpRouterApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadTheme(
        data: usLightTheme,
        child: MaterialApp.router(
          routerConfig: routerConfig,
          builder: (context, child) => ShadToaster(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('routerConfig', () {
    testWidgets('redirects unauthenticated users from shell pages to login', (
      tester,
    ) async {
      await pumpRouterApp(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(UsBottomNavBar), findsNothing);
    });

    testWidgets(
      'shows the shell after authenticating and guards it on logout',
      (tester) async {
        await pumpRouterApp(tester);
        expect(find.byType(LoginPage), findsOneWidget);

        // Authenticating flips the status signal, which triggers the router's
        // refreshListenable: /login is an auth route, so we land on /home.
        di<AuthViewModel>().authenticate(credentials);
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(UsBottomNavBar), findsOneWidget);

        // Branch switching through the nav bar works inside the real shell.
        await tester.tap(find.text('PROFILE'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfilePage), findsOneWidget);

        // Logging out from a shell branch bounces back to login.
        di<AuthViewModel>().unauthenticate();
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(UsBottomNavBar), findsNothing);
      },
    );
  });
}
