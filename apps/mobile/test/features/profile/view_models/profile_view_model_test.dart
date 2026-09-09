import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/auth/models/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
import 'package:uni_stash_mobile/features/profile/view_models/profile_view_model.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

User makeUser({String id = 'user-1'}) {
  return User(
    id: id,
    email: 'ada@unilag.edu.ng',
    displayName: 'Ada Lovelace',
    emailVerified: true,
    role: 'student',
  );
}

void main() {
  late MockProfileRepository mockRepository;
  late ProfileViewModel viewModel;

  setUp(() {
    mockRepository = MockProfileRepository();
    viewModel = ProfileViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('initial state', () {
    test('profile starts null', () {
      expect(viewModel.profile.value, isNull);
    });

    test('isLoading starts false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('error starts null', () {
      expect(viewModel.error.value, isNull);
    });
  });

  group('fetch', () {
    test('sets profile on success', () async {
      final user = makeUser();
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => Result.success(user),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.profile.value, user);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);
    });

    test('clears a stale error on a successful refetch', () async {
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => const Result.failure('No internet connection.'),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.error.value, isNotNull);

      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => Result.success(makeUser()),
      );
      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, isNull);
      expect(viewModel.profile.value, isNotNull);
    });

    test('sets error on failure', () async {
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => const Result.failure('Session expired.'),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.profile.value, isNull);
      expect(viewModel.error.value, 'Session expired.');
    });

    test('keeps the previous profile on failure', () async {
      final user = makeUser();
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => Result.success(user),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.profile.value, user);

      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => const Result.failure('Server error (500).'),
      );
      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.profile.value, user);
      expect(viewModel.error.value, 'Server error (500).');
    });

    test('isLoading goes true then false', () async {
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return Result.success(makeUser());
        },
      );

      viewModel.fetch();
      expect(viewModel.isLoading.value, true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.isLoading.value, false);
    });
  });

  group('reset', () {
    test('clears all state', () async {
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => Result.success(makeUser()),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.profile.value, isNotNull);

      viewModel.reset();

      expect(viewModel.profile.value, isNull);
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
    });
  });
}
