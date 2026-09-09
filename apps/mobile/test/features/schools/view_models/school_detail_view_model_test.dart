import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/view_models/school_detail_view_model.dart';

class MockSchoolsRepository extends Mock implements SchoolsRepository {}

School makeSchool({String id = 'school-1', String name = 'MIT'}) {
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
  late SchoolDetailViewModel viewModel;

  setUp(() {
    mockRepository = MockSchoolsRepository();
    viewModel = SchoolDetailViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('initial state', () {
    test('school starts null', () {
      expect(viewModel.school.value, isNull);
    });

    test('isLoading starts false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('error starts null', () {
      expect(viewModel.error.value, isNull);
    });
  });

  group('fetch', () {
    test('sets school on success', () async {
      final school = makeSchool();
      when(() => mockRepository.getSchool('school-1')).thenAnswer(
        (_) async => Result.success(school),
      );

      viewModel.fetch('school-1');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.school.value, school);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);
    });

    test('sets error on failure', () async {
      when(() => mockRepository.getSchool('bad-id')).thenAnswer(
        (_) async => const Result.failure('Not found'),
      );

      viewModel.fetch('bad-id');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.school.value, isNull);
      expect(viewModel.error.value, 'Not found');
    });

    test('isLoading goes true then false', () async {
      when(() => mockRepository.getSchool('school-1')).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return Result.success(makeSchool());
        },
      );

      viewModel.fetch('school-1');
      expect(viewModel.isLoading.value, true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.isLoading.value, false);
    });
  });

  group('reset', () {
    test('clears all state', () async {
      when(() => mockRepository.getSchool('school-1')).thenAnswer(
        (_) async => Result.success(makeSchool()),
      );

      viewModel.fetch('school-1');
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.school.value, isNotNull);

      viewModel.reset();

      expect(viewModel.school.value, isNull);
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
    });
  });
}
