import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';
import 'package:uni_stash_mobile/features/schools/view_models/schools_view_model.dart';

class MockSchoolsRepository extends Mock implements SchoolsRepository {}

School makeSchool({String id = 's1', String name = 'MIT'}) {
  return School(
    id: id,
    name: name,
    slug: name.toLowerCase(),
    domain: '${name.toLowerCase()}.edu',
    createdAt: DateTime(2025),
  );
}

void main() {
  late MockSchoolsRepository mockRepository;
  late SchoolsViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(const ListSchoolsQuery());
  });

  setUp(() {
    mockRepository = MockSchoolsRepository();
    viewModel = SchoolsViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('initial state', () {
    test('schools starts empty', () {
      expect(viewModel.schools.value, isEmpty);
    });

    test('isLoading starts false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('error starts null', () {
      expect(viewModel.error.value, isNull);
    });

    test('hasMore starts true', () {
      expect(viewModel.hasMore.value, true);
    });

    test('query starts empty', () {
      expect(viewModel.query.value, '');
    });
  });

  group('fetch - Success', () {
    test('populates schools on success', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(schools: [makeSchool()]),
        ),
      );

      viewModel.fetch();
      expect(viewModel.isLoading.value, true);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.schools.value.length, 1);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);
    });

    test('sets hasMore based on nextCursor', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(
            schools: [makeSchool()],
            nextCursor: 'next-page',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.hasMore.value, true);
    });

    test('sets hasMore to false when no nextCursor', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListSchoolsResponse(schools: []),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.hasMore.value, false);
    });

    test('passes search query to repository', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListSchoolsResponse(schools: []),
        ),
      );

      viewModel.query.value = 'stanford';
      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      final captured =
          verify(() => mockRepository.list(captureAny())).captured.single
              as ListSchoolsQuery;
      expect(captured.q, 'stanford');
    });
  });

  group('fetch - Failure', () {
    test('sets error message on failure', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.failure('Network error'),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Network error');
      expect(viewModel.schools.value, isEmpty);
      expect(viewModel.isLoading.value, false);
    });
  });

  group('loadMore', () {
    test('appends new schools to existing list', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(
            schools: [makeSchool(id: '1')],
            nextCursor: 'cursor-1',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.schools.value.length, 1);

      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(schools: [makeSchool(id: '2', name: 'Stanford')]),
        ),
      );

      viewModel.loadMore();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.schools.value.length, 2);
      expect(viewModel.schools.value[1].name, 'Stanford');
    });

    test('does nothing when hasMore is false', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListSchoolsResponse(schools: []),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      clearInteractions(mockRepository);

      viewModel.loadMore();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockRepository.list(any()));
    });
  });

  group('refresh', () {
    test('replaces schools with fresh data', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(
            schools: [makeSchool(id: '1')],
            nextCursor: 'old',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(
            schools: [
              makeSchool(id: 'a', name: 'Stanford'),
              makeSchool(id: 'b', name: 'Harvard'),
            ],
          ),
        ),
      );

      viewModel.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.schools.value.length, 2);
      expect(viewModel.schools.value.first.name, 'Stanford');
      expect(viewModel.hasMore.value, false);
    });
  });

  group('reset', () {
    test('clears all state', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListSchoolsResponse(
            schools: [makeSchool()],
            nextCursor: 'c',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      viewModel.reset();

      expect(viewModel.schools.value, isEmpty);
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
      expect(viewModel.hasMore.value, true);
      expect(viewModel.query.value, '');
    });
  });
}
