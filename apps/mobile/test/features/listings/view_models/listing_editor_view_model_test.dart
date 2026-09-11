import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listing_editor_view_model.dart';

class MockListingsRepository extends Mock implements ListingsRepository {}

class MockCategoriesRepository extends Mock implements CategoriesRepository {}

Category makeCategory({
  int id = 1,
  String slug = 'textbooks',
  String label = 'Textbooks',
}) {
  return Category(id: id, slug: slug, label: label);
}

void main() {
  late MockListingsRepository mockRepository;
  late MockCategoriesRepository mockCategoriesRepository;
  late ListingEditorViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(
      const CreateListingRequest(
        title: '',
        condition: Condition.isNew,
        categoryId: 1,
      ),
    );
  });

  setUp(() {
    mockRepository = MockListingsRepository();
    mockCategoriesRepository = MockCategoriesRepository();
    // The ViewModel fetches categories in its constructor.
    when(() => mockCategoriesRepository.list()).thenAnswer(
      (_) async => const Success(
        ListCategoriesResponse(categories: []),
      ),
    );
    viewModel = ListingEditorViewModel(
      mockRepository,
      mockCategoriesRepository,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  // =========================================================================
  // GROUP: Categories loading
  // =========================================================================

  group('categories loading', () {
    test('fetches categories from the repository on construction', () async {
      // Let the constructor-triggered fetch settle.
      await Future<void>.delayed(Duration.zero);

      verify(() => mockCategoriesRepository.list()).called(1);
    });

    test('populates categories on success', () async {
      when(() => mockCategoriesRepository.list()).thenAnswer(
        (_) async => Success(
          ListCategoriesResponse(
            categories: [
              makeCategory(),
              makeCategory(id: 2, slug: 'electronics', label: 'Electronics'),
            ],
          ),
        ),
      );

      await viewModel.loadCategories();

      expect(viewModel.categories.value, hasLength(2));
      expect(viewModel.categories.value[0].label, 'Textbooks');
      expect(viewModel.isLoadingCategories.value, isFalse);
      expect(viewModel.categoriesError.value, isNull);
    });

    test('sets categoriesError on failure and keeps list empty', () async {
      when(() => mockCategoriesRepository.list()).thenAnswer(
        (_) async => const Failure('network down'),
      );

      await viewModel.loadCategories();

      expect(viewModel.categories.value, isEmpty);
      expect(viewModel.categoriesError.value, 'network down');
      expect(viewModel.isLoadingCategories.value, isFalse);
    });

    test('toggles isLoadingCategories around the fetch', () async {
      final completer = Completer<Result<ListCategoriesResponse>>();
      when(() => mockCategoriesRepository.list()).thenAnswer(
        (_) => completer.future,
      );

      final loading = viewModel.loadCategories();
      expect(viewModel.isLoadingCategories.value, isTrue);

      completer.complete(
        const Success(ListCategoriesResponse(categories: [])),
      );
      await loading;
      expect(viewModel.isLoadingCategories.value, isFalse);
    });

    test('clears a previous error on a successful retry', () async {
      when(() => mockCategoriesRepository.list()).thenAnswer(
        (_) async => const Failure('network down'),
      );
      await viewModel.loadCategories();
      expect(viewModel.categoriesError.value, isNotNull);

      when(() => mockCategoriesRepository.list()).thenAnswer(
        (_) async => Success(
          ListCategoriesResponse(categories: [makeCategory()]),
        ),
      );
      await viewModel.loadCategories();

      expect(viewModel.categoriesError.value, isNull);
      expect(viewModel.categories.value, hasLength(1));
    });
  });

  // =========================================================================
  // GROUP: Submit (regression — unchanged mapping)
  // =========================================================================

  group('submit', () {
    test('passes the selected category id through to the request', () async {
      when(() => mockRepository.create(any())).thenAnswer(
        (_) async => Success(_makeListing()),
      );

      await viewModel.submit({
        'title': 'Test Title',
        'description': 'Test Description',
        'category': makeCategory(id: 7),
        'condition': Condition.used,
        'price': '5,000',
      });

      final captured =
          verify(
                () => mockRepository.create(captureAny()),
              ).captured.single
              as CreateListingRequest;
      expect(captured.categoryId, 7);
    });
  });
}

Listing _makeListing() {
  return Listing(
    id: 'listing-1',
    sellerId: 'seller-1',
    categoryId: 7,
    title: 'Test Listing',
    description: 'Description',
    condition: Condition.isNew,
    status: ListingStatus.active,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );
}
