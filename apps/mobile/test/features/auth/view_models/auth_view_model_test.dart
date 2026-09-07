import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/data/auth_repository.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

const _verifiedUser = User(
  id: 'test-uuid-123',
  email: 'test@example.com',
  displayName: 'Test User',
  emailVerified: true,
  role: 'student',
);

const _unverifiedUser = User(
  id: 'test-uuid-456',
  email: 'unverified@example.com',
  displayName: 'New User',
  emailVerified: false,
  role: 'student',
);

UserCredentials makeCredentials({User user = _verifiedUser}) {
  return UserCredentials(
    user: user,
    accessToken: 'access_token_123',
    refreshToken: 'refresh_token_123',
    expiresIn: 900,
  );
}

void main() {
  late MockAuthRepository mockRepository;
  late MockFlutterSecureStorage mockStorage;
  late AuthViewModel viewModel;

  /// authenticate/unauthenticate are `void` actions whose storage writes and
  /// signal updates complete on microtasks — let them flush before asserting.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    mockRepository = MockAuthRepository();
    mockStorage = MockFlutterSecureStorage();

    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockStorage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});

    viewModel = AuthViewModel(mockRepository, mockStorage);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('initial state', () {
    test('status starts as loading', () {
      expect(viewModel.status.value, AuthStatus.loading);
    });

    test('user and verified start cleared', () {
      expect(viewModel.user.value, isNull);
      expect(viewModel.verified.value, isFalse);
    });
  });

  group('bootstrap', () {
    test('with no stored token ends up unauthenticated', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) async => null,
      );

      await viewModel.bootstrap();

      expect(viewModel.status.value, AuthStatus.unauthenticated);
      expect(viewModel.user.value, isNull);
      verifyNever(() => mockRepository.me());
    });

    test('with an empty stored token ends up unauthenticated', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) async => '',
      );

      await viewModel.bootstrap();

      expect(viewModel.status.value, AuthStatus.unauthenticated);
      verifyNever(() => mockRepository.me());
    });

    test(
      'with a token and a verified profile restores an authenticated, '
      'verified session',
      () async {
        when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
          (_) async => 'stored_access_token',
        );
        when(() => mockRepository.me()).thenAnswer(
          (_) async => const Result.success(_verifiedUser),
        );

        await viewModel.bootstrap();

        expect(viewModel.status.value, AuthStatus.authenticated);
        expect(viewModel.user.value, _verifiedUser);
        expect(viewModel.verified.value, isTrue);
      },
    );

    test(
      'with a token and an unverified profile restores an authenticated '
      'but unverified session (so the router can bounce it to /verify)',
      () async {
        when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
          (_) async => 'stored_access_token',
        );
        when(() => mockRepository.me()).thenAnswer(
          (_) async => const Result.success(_unverifiedUser),
        );

        await viewModel.bootstrap();

        expect(viewModel.status.value, AuthStatus.authenticated);
        expect(viewModel.user.value, _unverifiedUser);
        expect(viewModel.verified.value, isFalse);
      },
    );

    test('clears tokens and signs out when the profile fetch fails', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) async => 'stored_access_token',
      );
      when(() => mockRepository.me()).thenAnswer(
        (_) async => const Result.failure('Session expired'),
      );

      await viewModel.bootstrap();

      expect(viewModel.status.value, AuthStatus.unauthenticated);
      expect(viewModel.user.value, isNull);
      expect(viewModel.verified.value, isFalse);
      verify(
        () => mockStorage.delete(key: any(named: 'key')),
      ).called(2); // access + refresh tokens
    });
  });

  group('authenticate', () {
    test('stores tokens and marks the session authenticated + verified',
        () async {
      viewModel.authenticate(makeCredentials());
      await flush();

      verify(
        () => mockStorage.write(key: 'access_token', value: 'access_token_123'),
      ).called(1);
      verify(
        () => mockStorage.write(
          key: 'refresh_token',
          value: 'refresh_token_123',
        ),
      ).called(1);
      expect(viewModel.status.value, AuthStatus.authenticated);
      expect(viewModel.user.value, _verifiedUser);
      expect(viewModel.verified.value, isTrue);
    });

    test('keeps the session authenticated but unverified for a new account',
        () async {
      viewModel.authenticate(makeCredentials(user: _unverifiedUser));
      await flush();

      expect(viewModel.status.value, AuthStatus.authenticated);
      expect(viewModel.verified.value, isFalse);
    });

    test('flips verified after re-authenticating with a verified user',
        () async {
      viewModel.authenticate(makeCredentials(user: _unverifiedUser));
      await flush();
      expect(viewModel.verified.value, isFalse);

      // Same status as before (still authenticated): only the verification
      // state changes — this is what the router must react to on /verify.
      viewModel.authenticate(makeCredentials());
      await flush();

      expect(viewModel.status.value, AuthStatus.authenticated);
      expect(viewModel.user.value, _verifiedUser);
      expect(viewModel.verified.value, isTrue);
    });
  });

  group('unauthenticate', () {
    test('clears tokens, user and verification state', () async {
      viewModel.authenticate(makeCredentials());
      await flush();
      expect(viewModel.verified.value, isTrue);

      viewModel.unauthenticate();
      await flush();

      expect(viewModel.status.value, AuthStatus.unauthenticated);
      expect(viewModel.user.value, isNull);
      expect(viewModel.verified.value, isFalse);
      verify(
        () => mockStorage.delete(key: any(named: 'key')),
      ).called(2);
    });
  });

  group('routerRefresh', () {
    test('emits when the session signs in and out', () async {
      final observed = <Object?>[];
      final dispose = viewModel.routerRefresh.subscribe(observed.add);

      viewModel.authenticate(makeCredentials());
      await flush();
      viewModel.unauthenticate();
      await flush();

      expect(observed, isNotEmpty);
      dispose();
    });

    test('emits when verification changes while staying signed in', () async {
      final observed = <Object?>[];
      final dispose = viewModel.routerRefresh.subscribe(observed.add);

      viewModel.authenticate(makeCredentials(user: _unverifiedUser));
      await flush();
      viewModel.authenticate(makeCredentials());
      await flush();

      // The unverified -> verified transition must produce an emission even
      // though the auth status never left `authenticated`.
      expect(observed.length, greaterThanOrEqualTo(2));
      dispose();
    });
  });

  group('token accessors', () {
    test('readAccessToken/readRefreshToken proxy the secure storage', () async {
      when(() => mockStorage.read(key: 'access_token')).thenAnswer(
        (_) async => 'access',
      );
      when(() => mockStorage.read(key: 'refresh_token')).thenAnswer(
        (_) async => 'refresh',
      );

      expect(await viewModel.readAccessToken(), 'access');
      expect(await viewModel.readRefreshToken(), 'refresh');
    });
  });
}
