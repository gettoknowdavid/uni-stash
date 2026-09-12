import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listing_detail_view_model.dart';

class MockListingsRepository extends Mock implements ListingsRepository {}

ListingDetailResponse makeDetail({String id = 'listing-1'}) {
  return ListingDetailResponse(
    id: id,
    title: 'Detail Listing',
    description: 'Detailed description',
    condition: Condition.isNew,
    status: ListingStatus.active,
    createdAt: DateTime(2025),
    seller: const Seller(id: 'seller-1', displayName: 'Seller Name'),
    category: const Category(id: 1, slug: 'electronics', label: 'Electronics'),
    images: const [],
    price: const Money(amountMinor: 42),
  );
}

void main() {
  late MockListingsRepository mockRepository;
  late ListingDetailViewModel viewModel;

  setUp(() {
    mockRepository = MockListingsRepository();
    viewModel = ListingDetailViewModel(mockRepository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  // =========================================================================
  // GROUP: Initial State
  // =========================================================================
  group('initial state', () {
    test('detail starts null', () {
      expect(viewModel.detail.value, isNull);
    });

    test('isLoading starts false', () {
      expect(viewModel.isLoading.value, false);
    });

    test('error starts null', () {
      expect(viewModel.error.value, isNull);
    });
  });

  // =========================================================================
  // GROUP: fetch
  // =========================================================================
  group('fetch', () {
    test('sets detail on success', () async {
      final detail = makeDetail();
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async => Result.success(detail),
      );

      viewModel.fetch('listing-1');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.detail.value, detail);
      expect(viewModel.error.value, isNull);
      expect(viewModel.isLoading.value, false);
    });

    test('sets error on failure', () async {
      when(() => mockRepository.getListing('bad-id')).thenAnswer(
        (_) async => const Result.failure('Not found'),
      );

      viewModel.fetch('bad-id');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.detail.value, isNull);
      expect(viewModel.error.value, 'Not found');
    });

    test('isLoading goes true then false', () async {
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return Result.success(makeDetail());
        },
      );

      viewModel.fetch('listing-1');
      expect(viewModel.isLoading.value, true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.isLoading.value, false);
    });
  });

  // =========================================================================
  // GROUP: reserve
  // =========================================================================
  group('reserve', () {
    test('reloads detail after successful reserve', () async {
      final detail = makeDetail();
      when(() => mockRepository.reserve('listing-1')).thenAnswer(
        (_) async => Result.success(
          Listing(
            id: 'listing-1',
            sellerId: 'seller-1',
            categoryId: 1,
            title: 'Detail Listing',
            description: 'Detailed description',
            condition: Condition.isNew,
            status: ListingStatus.reserved,
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
          ),
        ),
      );
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async => Result.success(detail),
      );

      viewModel.reserve('listing-1');
      await Future<void>.delayed(Duration.zero);

      verify(() => mockRepository.reserve('listing-1')).called(1);
      verify(() => mockRepository.getListing('listing-1')).called(1);
      expect(viewModel.detail.value, detail);
    });

    test('sets error on reserve failure', () async {
      when(() => mockRepository.reserve('listing-1')).thenAnswer(
        (_) async => const Result.failure('Already reserved'),
      );

      viewModel.reserve('listing-1');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Already reserved');
      verifyNever(() => mockRepository.getListing(any()));
    });
  });

  // =========================================================================
  // GROUP: unreserve
  // =========================================================================
  group('unreserve', () {
    test('reloads detail after successful unreserve', () async {
      when(() => mockRepository.unreserve('listing-1')).thenAnswer(
        (_) async => Result.success(
          Listing(
            id: 'listing-1',
            sellerId: 'seller-1',
            categoryId: 1,
            title: 'Detail Listing',
            description: 'Detailed description',
            condition: Condition.isNew,
            status: ListingStatus.active,
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
          ),
        ),
      );
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async => Result.success(makeDetail()),
      );

      viewModel.unreserve('listing-1');
      await Future<void>.delayed(Duration.zero);

      verify(() => mockRepository.unreserve('listing-1')).called(1);
      verify(() => mockRepository.getListing('listing-1')).called(1);
    });

    test('sets error on unreserve failure', () async {
      when(() => mockRepository.unreserve('listing-1')).thenAnswer(
        (_) async => const Result.failure('Not reserved'),
      );

      viewModel.unreserve('listing-1');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Not reserved');
    });
  });

  // =========================================================================
  // GROUP: markAsSold
  // =========================================================================
  group('markAsSold', () {
    test('reloads detail after successful markAsSold', () async {
      when(() => mockRepository.markAsSold('listing-1')).thenAnswer(
        (_) async => Result.success(
          Listing(
            id: 'listing-1',
            sellerId: 'seller-1',
            categoryId: 1,
            title: 'Detail Listing',
            description: 'Detailed description',
            condition: Condition.isNew,
            status: ListingStatus.sold,
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
          ),
        ),
      );
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async => Result.success(makeDetail()),
      );

      viewModel.markAsSold('listing-1');
      await Future<void>.delayed(Duration.zero);

      verify(() => mockRepository.markAsSold('listing-1')).called(1);
      verify(() => mockRepository.getListing('listing-1')).called(1);
    });

    test('sets error on markAsSold failure', () async {
      when(() => mockRepository.markAsSold('listing-1')).thenAnswer(
        (_) async => const Result.failure('Cannot mark as sold'),
      );

      viewModel.markAsSold('listing-1');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.error.value, 'Cannot mark as sold');
    });
  });

  // =========================================================================
  // GROUP: reset
  // =========================================================================
  group('reset', () {
    test('clears all state', () async {
      when(() => mockRepository.getListing('listing-1')).thenAnswer(
        (_) async => Result.success(makeDetail()),
      );
      viewModel.fetch('listing-1');
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.detail.value, isNotNull);

      viewModel.reset();

      expect(viewModel.detail.value, isNull);
      expect(viewModel.isLoading.value, false);
      expect(viewModel.error.value, isNull);
    });
  });
}
