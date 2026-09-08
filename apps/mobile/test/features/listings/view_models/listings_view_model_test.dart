import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listings_view_model.dart';

class MockListingsRepository extends Mock implements ListingsRepository {}

Listing makeListing({String id = 'uuid-1', String title = 'Listing'}) {
  return Listing(
    id: id,
    sellerId: 'seller-1',
    categoryId: 1,
    title: title,
    description: 'Description',
    condition: Condition.isNew,
    status: ListingStatus.active,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
    price: 10,
  );
}

void main() {
  late MockListingsRepository mockRepository;
  late ListingsViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(const ListListingsQuery());
  });

  setUp(() {
    mockRepository = MockListingsRepository();
    viewModel = ListingsViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  // =========================================================================
  // GROUP: Initial State
  // =========================================================================
  group('initial state', () {
    test('listings starts empty', () {
      expect(viewModel.listings.value, isEmpty);
    });

    test('isLoading starts false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('isLoadingMore starts false', () {
      expect(viewModel.isLoadingMore.value, false);
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

    test('categoryId starts null', () {
      expect(viewModel.categoryId.value, isNull);
    });
  });

  // =========================================================================
  // GROUP: fetch - Success
  // =========================================================================
  group('fetch - Success', () {
    test('populates listings on success', () async {
      final listing = makeListing();
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(listings: [listing]),
        ),
      );

      viewModel.fetch();
      // isLoading goes true synchronously
      expect(viewModel.isLoading.value, true);

      await Future<void>.delayed(Duration.zero);

      expect(viewModel.listings.value.length, 1);
      expect(viewModel.listings.value.first.title, 'Listing');
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);
    });

    test('sets hasMore to false when nextCursor is null', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListListingsResponse(listings: []),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.hasMore.value, false);
    });

    test('sets hasMore to true when nextCursor is present', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListListingsResponse(
            listings: [],
            nextCursor: 'next-page',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.hasMore.value, true);
    });

    test('passes search query to repository', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListListingsResponse(listings: []),
        ),
      );

      viewModel.query.value = 'laptop';
      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => mockRepository.list(captureAny()))
          .captured
          .single as ListListingsQuery;
      expect(captured.q, 'laptop');
    });

    test('passes categoryId to repository', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListListingsResponse(listings: []),
        ),
      );

      viewModel.categoryId.value = 7;
      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => mockRepository.list(captureAny()))
          .captured
          .single as ListListingsQuery;
      expect(captured.categoryId, 7);
    });
  });

  // =========================================================================
  // GROUP: fetch - Failure
  // =========================================================================
  group('fetch - Failure', () {
    test('sets error message on failure', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.failure('Network error'),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Network error');
      expect(viewModel.listings.value, isEmpty);
      expect(viewModel.isLoading.value, false);
    });
  });

  // =========================================================================
  // GROUP: loadMore
  // =========================================================================
  group('loadMore', () {
    test('appends new listings to existing list', () async {
      // First fetch
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(
            listings: [makeListing(id: '1', title: 'First')],
            nextCursor: 'cursor-1',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.listings.value.length, 1);

      // Second fetch (loadMore)
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(
            listings: [makeListing(id: '2', title: 'Second')],
          ),
        ),
      );

      viewModel.loadMore();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.listings.value.length, 2);
      expect(viewModel.listings.value[1].title, 'Second');
    });

    test('does nothing when hasMore is false', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => const Result.success(
          ListListingsResponse(listings: []),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);

      clearInteractions(mockRepository);

      // hasMore is now false; loadMore should no-op
      viewModel.loadMore();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockRepository.list(any()));
    });
  });

  // =========================================================================
  // GROUP: refresh
  // =========================================================================
  group('refresh', () {
    test('replaces listings with fresh data', () async {
      // Initial fetch
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(
            listings: [makeListing(id: '1')],
            nextCursor: 'cursor-old',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.listings.value.length, 1);

      // Refresh
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(
            listings: [
              makeListing(id: 'a', title: 'Fresh'),
              makeListing(id: 'b', title: 'Fresh2'),
            ],
          ),
        ),
      );

      viewModel.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.listings.value.length, 2);
      expect(viewModel.listings.value.first.title, 'Fresh');
      expect(viewModel.hasMore.value, false);
    });
  });

  // =========================================================================
  // GROUP: reset
  // =========================================================================
  group('reset', () {
    test('clears all state', () async {
      when(() => mockRepository.list(any())).thenAnswer(
        (_) async => Result.success(
          ListListingsResponse(
            listings: [makeListing()],
            nextCursor: 'c',
          ),
        ),
      );

      viewModel.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.listings.value.length, 1);

      viewModel.reset();

      expect(viewModel.listings.value, isEmpty);
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
      expect(viewModel.hasMore.value, true);
      expect(viewModel.query.value, '');
      expect(viewModel.categoryId.value, isNull);
    });
  });

  // =========================================================================
  // GROUP: Signal Reactivity
  // =========================================================================
  group('signal reactivity', () {
    test('query signal notifies subscribers', () {
      String? captured;
      final dispose = viewModel.query.subscribe((v) => captured = v);
      viewModel.query.value = 'phone';
      expect(captured, 'phone');
      dispose();
    });

    test('categoryId signal notifies subscribers', () {
      int? captured;
      final dispose = viewModel.categoryId.subscribe((v) => captured = v);
      viewModel.categoryId.value = 5;
      expect(captured, 5);
      dispose();
    });
  });
}
