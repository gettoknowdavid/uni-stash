// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
// import 'package:mocktail/mocktail.dart';
// import 'package:shadcn_ui/shadcn_ui.dart';
// import 'package:uni_stash_mobile/core/config/di.dart';
// import 'package:uni_stash_mobile/core/result/result.dart';
// import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
// import 'package:uni_stash_mobile/features/auth/models/auth_dto.dart';
// import 'package:uni_stash_mobile/features/auth/models/models.dart';
// import 'package:uni_stash_mobile/features/auth/pages/login_page.dart';
// import 'package:uni_stash_mobile/features/auth/pages/verify_page.dart';
// import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
// import 'package:uni_stash_mobile/features/listings/pages/home_page.dart';
// import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
// import 'package:uni_stash_mobile/features/profile/pages/profile_page.dart';
// import 'package:uni_stash_mobile/router/us_router.dart';
// import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
// import 'package:uni_stash_mobile/theme/_theme.dart';

// class MockAuthRepository extends Mock implements IAuthRepository {}

// class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// class _StubProfileRepository implements ProfileRepository {
//   const _StubProfileRepository();

//   @override
//   Future<Result<User>> getProfile() async => const Result.success(
//     User(
//       id: 'test-uuid-123',
//       email: 'test@example.com',
//       displayName: 'Test User',
//       emailVerified: true,
//       role: 'student',
//     ),
//   );
// }

// void main() {
//   const verifiedUser = User(
//     id: 'test-uuid-123',
//     email: 'test@example.com',
//     displayName: 'Test User',
//     emailVerified: true,
//     role: 'student',
//   );

//   const unverifiedUser = User(
//     id: 'test-uuid-456',
//     email: 'unverified@example.com',
//     displayName: 'New User',
//     emailVerified: false,
//     role: 'student',
//   );

//   const credentials = UserCredentials(
//     user: verifiedUser,
//     accessToken: 'test_access_token',
//     refreshToken: 'test_refresh_token',
//     expiresIn: 900,
//   );

//   late MockAuthRepository mockRepo;
//   late MockFlutterSecureStorage mockStorage;

//   setUpAll(() {
//     registerFallbackValue(
//       const VerifyOtpRequest(code: '123456', otpType: 'email_verify'),
//     );

//     mockRepo = MockAuthRepository();
//     mockStorage = MockFlutterSecureStorage();

//     when(
//       () => mockStorage.write(
//         key: any(named: 'key'),
//         value: any(named: 'value'),
//       ),
//     ).thenAnswer((_) async {});
//     when(
//       () => mockStorage.delete(key: any(named: 'key')),
//     ).thenAnswer((_) async {});

//     // One AuthViewModel for the whole file: the router's refreshListenable
//     // subscribes to its status signal on first use, so reusing the instance
//     // keeps the redirect listener alive across tests.
//     di.pushNewScope(
//       scopeName: 'routerTest',
//       init: (getIt) {
//         getIt.registerSingleton<IAuthRepository>(mockRepo);
//         getIt.registerSingleton<FlutterSecureStorage>(mockStorage);
//         getIt.registerLazySingleton<AuthViewModel>(
//           () => AuthViewModel(
//             getIt<IAuthRepository>(),
//             getIt<FlutterSecureStorage>(),
//           ),
//         );
//         // ProfilePage (a shell branch) fetches through ProfileRepository on
//         // open; these tests don't exercise profile data, so a canned success
//         // stub keeps the shell visit side-effect free.
//         getIt.registerSingleton<ProfileRepository>(_StubProfileRepository());
//       },
//     );
//   });

//   setUp(() {
//     // Reset to a clean, unauthenticated state for every test.
//     di<AuthViewModel>().unauthenticate();
//   });

//   tearDownAll(() async {
//     // Pop any page scope left behind (e.g. LoginPage), then the test scope.
//     while (di.currentScopeName != 'routerTest') {
//       await di.popScope();
//     }
//     await di.popScope();
//   });

//   /// Simulates an app start/restart with a stored session by bootstrapping
//   /// the shared AuthViewModel against the given stored profile.
//   Future<void> bootstrapStoredSession(
//     WidgetTester tester, {
//     required String? storedAccessToken,
//     required User profile,
//   }) async {
//     when(() => mockStorage.read(key: 'access_token')).thenAnswer(
//       (_) async => storedAccessToken,
//     );
//     when(() => mockRepo.me()).thenAnswer(
//       (_) async => Result.success(profile),
//     );

//     await di<AuthViewModel>().bootstrap();
//     await tester.pumpAndSettle();
//   }

//   Future<void> pumpRouterApp(WidgetTester tester) async {
//     await tester.pumpWidget(
//       ShadTheme(
//         data: usLightTheme,
//         child: MaterialApp.router(
//           routerConfig: routerConfig,
//           builder: (context, child) => ShadToaster(child: child!),
//         ),
//       ),
//     );
//     await tester.pumpAndSettle();
//   }

//   group('routerConfig', () {
//     testWidgets('redirects unauthenticated users from shell pages to login', (
//       tester,
//     ) async {
//       await pumpRouterApp(tester);

//       expect(find.byType(LoginPage), findsOneWidget);
//       expect(find.byType(UsBottomNavBar), findsNothing);
//     });

//     testWidgets(
//       'shows the shell after authenticating and guards it on logout',
//       (tester) async {
//         await pumpRouterApp(tester);
//         expect(find.byType(LoginPage), findsOneWidget);

//         // Authenticating flips the status signal, which triggers the router's
//         // refreshListenable: /login is an auth route, so we land on /home.
//         di<AuthViewModel>().authenticate(credentials);
//         await tester.pumpAndSettle();

//         expect(find.byType(HomePage), findsOneWidget);
//         expect(find.byType(UsBottomNavBar), findsOneWidget);

//         // Branch switching through the nav bar works inside the real shell.
//         await tester.tap(find.text('PROFILE'));
//         await tester.pumpAndSettle();
//         expect(find.byType(ProfilePage), findsOneWidget);

//         // Logging out from a shell branch bounces back to login.
//         di<AuthViewModel>().unauthenticate();
//         await tester.pumpAndSettle();
//         expect(find.byType(LoginPage), findsOneWidget);
//         expect(find.byType(UsBottomNavBar), findsNothing);
//       },
//     );

//     group('verification-aware routing', () {
//       testWidgets(
//         'restarting with an unverified stored session lands on /verify, '
//         'not the shell',
//         (tester) async {
//           await pumpRouterApp(tester);
//           expect(find.byType(LoginPage), findsOneWidget);

//           await bootstrapStoredSession(
//             tester,
//             storedAccessToken: 'stored_access_token',
//             profile: unverifiedUser,
//           );

//           expect(find.byType(VerifyPage), findsOneWidget);
//           expect(find.byType(HomePage), findsNothing);
//           expect(find.byType(LoginPage), findsNothing);
//         },
//       );

//       testWidgets('restarting with a verified stored session lands on home', (
//         tester,
//       ) async {
//         await pumpRouterApp(tester);

//         await bootstrapStoredSession(
//           tester,
//           storedAccessToken: 'stored_access_token',
//           profile: verifiedUser,
//         );

//         expect(find.byType(HomePage), findsOneWidget);
//         expect(find.byType(VerifyPage), findsNothing);
//       });

//       testWidgets(
//         'an unverified session is pinned to /verify and enters the shell '
//         'only after the OTP succeeds',
//         (tester) async {
//           await pumpRouterApp(tester);
//           await bootstrapStoredSession(
//             tester,
//             storedAccessToken: 'stored_access_token',
//             profile: unverifiedUser,
//           );
//           expect(find.byType(VerifyPage), findsOneWidget);
//           expect(find.byType(LoginPage), findsNothing);

//           // Even an explicit attempt to reach the shell is redirected back.
//           routerConfig.go('/home');
//           await tester.pumpAndSettle();
//           expect(find.byType(VerifyPage), findsOneWidget);
//           expect(find.byType(HomePage), findsNothing);

//           // A successful OTP submission returns fresh tokens + a verified
//           // profile; authenticating with them must let the session through.
//           when(() => mockRepo.verifyOtp(any())).thenAnswer(
//             (_) async => const Result.success(
//               VerifyOtpResponse(
//                 verified: true,
//                 accessToken: 'new_access',
//                 refreshToken: 'new_refresh',
//                 expiresIn: 900,
//                 user: verifiedUser,
//               ),
//             ),
//           );

//           // Seed the OTP input via the page's route query param (code=) and
//           // submit through the real VERIFY button. This avoids depending on
//           // GetIt scope resolution for the page-scoped ViewModel.
//           routerConfig.go(
//             '/verify?email=${Uri.encodeQueryComponent(unverifiedUser.email)}&code=123456',
//           );
//           await tester.pumpAndSettle();

//           await tester.tap(find.text('VERIFY'));
//           await tester.pumpAndSettle();

//           expect(di<AuthViewModel>().verified.value, isTrue);
//           expect(find.byType(HomePage), findsOneWidget);
//           expect(find.byType(VerifyPage), findsNothing);
//         },
//       );

//       testWidgets('a verified user cannot reach /verify', (tester) async {
//         await pumpRouterApp(tester);
//         di<AuthViewModel>().authenticate(credentials);
//         await tester.pumpAndSettle();
//         expect(find.byType(HomePage), findsOneWidget);

//         routerConfig.go('/verify');
//         await tester.pumpAndSettle();

//         expect(find.byType(HomePage), findsOneWidget);
//         expect(find.byType(VerifyPage), findsNothing);
//       });
//     });
//   });
// }
