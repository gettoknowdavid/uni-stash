import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_api.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

class MockListingsApiClient extends Mock implements ListingsApiClient {}

class MockLogger extends Mock implements Logger {}

Listing makeListing({
  String id = 'listing-uuid-001',
  String title = 'Test Listing',
  ListingStatus status = ListingStatus.active,
}) {
  return Listing(
    id: id,
    sellerId: 'seller-uuid-001',
    categoryId: 1,
    title: title,
    description: 'A test listing description',
    condition: Condition.isNew,
    status: status,
    createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
    updatedAt: DateTime.parse('2025-01-01T00:00:00Z'),
    price: const Money(amountMinor: 9999),
  );
}

ListingSummary makeListingSummary({
  String id = 'listing-uuid-001',
  String title = 'Test Listing',
  ListingStatus status = ListingStatus.active,
}) {
  return ListingSummary(
    id: id,
    title: title,
    condition: Condition.isNew,
    status: status,
    createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
    price: const Money(amountMinor: 9999),
  );
}

DioException makeDioException({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? responseData,
}) {
  return DioException(
    type: type,
    requestOptions: RequestOptions(path: '/api/v1/listings'),
    response: (responseData != null || statusCode != null)
        ? Response(
            data: responseData,
            statusCode: statusCode,
            requestOptions: RequestOptions(path: '/api/v1/listings'),
          )
        : null,
  );
}

void main() {
  late MockListingsApiClient mockApiClient;
  late MockLogger mockLogger;
  late ListingsRepository repository;

  setUpAll(() {
    registerFallbackValue(
      const CreateListingRequest(
        title: '',
        condition: Condition.isNew,
        categoryId: 1,
      ),
    );
    registerFallbackValue(
      const UpdateListingRequest(),
    );
  });

  setUp(() {
    mockApiClient = MockListingsApiClient();
    mockLogger = MockLogger();
    repository = ListingsRepositoryImpl(mockApiClient, mockLogger);
  });

  // =========================================================================
  // GROUP: create
  // =========================================================================
  group('create', () {
    test('returns Success with Listing on valid response', () async {
      final listing = makeListing(title: 'Created Listing');
      when(() => mockApiClient.create(any())).thenAnswer(
        (_) async => ApiResponse<Listing>(
          status: true,
          message: 'ok',
          data: listing,
        ),
      );
      final result = await repository.create(
        const CreateListingRequest(
          title: 'Created Listing',
          condition: Condition.isNew,
          categoryId: 1,
          price: Money(amountMinor: 50),
        ),
      );

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.title, 'Created Listing');
      }
    });

    test('returns Failure when API status is false', () async {
      when(() => mockApiClient.create(any())).thenAnswer(
        (_) async => const ApiResponse<Listing>(
          status: false,
          message: 'Validation failed',
        ),
      );

      final result = await repository.create(
        const CreateListingRequest(
          title: 'Bad',
          condition: Condition.isNew,
          categoryId: 1,
        ),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Validation failed');
      }
    });

    test('returns Failure on DioException', () async {
      when(() => mockApiClient.create(any())).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      final result = await repository.create(
        const CreateListingRequest(
          title: 'Offline',
          condition: Condition.isNew,
          categoryId: 1,
        ),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('internet connection'));
      }
    });

    test('returns generic failure on unexpected error', () async {
      when(() => mockApiClient.create(any())).thenThrow(
        Exception('kaboom'),
      );

      final result = await repository.create(
        const CreateListingRequest(
          title: 'Oops',
          condition: Condition.isNew,
          categoryId: 1,
        ),
      );

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'An unexpected error occurred.');
      }
    });
  });

  // =========================================================================
  // GROUP: list
  // =========================================================================
  group('list', () {
    test('returns Success with ListListingsResponse', () async {
      final listing = makeListingSummary();
      when(
        () => mockApiClient.getList(
          q: any(named: 'q'),
          categoryId: any(named: 'categoryId'),
          minPrice: any(named: 'minPrice'),
          maxPrice: any(named: 'maxPrice'),
          status: any(named: 'status'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse<ListListingsResponse>(
          status: true,
          message: 'ok',
          data: ListListingsResponse(
            listings: [listing],
            nextCursor: 'cursor-abc',
          ),
        ),
      );
      final result = await repository.list(
        const ListListingsQuery(q: 'test', limit: 10),
      );

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.listings.length, 1);
        expect(value.nextCursor, 'cursor-abc');
      }
    });

    test('passes query parameters to the API client', () async {
      when(
        () => mockApiClient.getList(
          q: any(named: 'q'),
          categoryId: any(named: 'categoryId'),
          minPrice: any(named: 'minPrice'),
          maxPrice: any(named: 'maxPrice'),
          status: any(named: 'status'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse<ListListingsResponse>(
          status: true,
          message: 'ok',
          data: ListListingsResponse(listings: []),
        ),
      );

      await repository.list(
        const ListListingsQuery(
          q: 'phone',
          categoryId: 5,
          minPrice: 10,
          maxPrice: 100,
          status: ListingStatus.active,
          cursor: 'prev-cursor',
          limit: 20,
        ),
      );

      verify(
        () => mockApiClient.getList(
          q: 'phone',
          categoryId: 5,
          minPrice: 10,
          maxPrice: 100,
          status: ListingStatus.active,
          cursor: 'prev-cursor',
          limit: 20,
        ),
      ).called(1);
    });

    test('returns Failure on DioException', () async {
      when(
        () => mockApiClient.getList(
          q: any(named: 'q'),
          categoryId: any(named: 'categoryId'),
          minPrice: any(named: 'minPrice'),
          maxPrice: any(named: 'maxPrice'),
          status: any(named: 'status'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(
        makeDioException(statusCode: 500),
      );

      final result = await repository.list(const ListListingsQuery());

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('Server error'));
      }
    });
  });

  // =========================================================================
  // GROUP: getListing
  // =========================================================================
  group('getListing', () {
    test('returns Success with ListingDetailResponse', () async {
      when(() => mockApiClient.getListing('listing-123')).thenAnswer(
        (_) async => const ApiResponse<ListingDetailResponse?>(
          status: true,
          message: 'ok',
        ),
      );

      final result = await repository.getListing('listing-123');

      expect(result.isSuccess, true);
      verify(() => mockApiClient.getListing('listing-123')).called(1);
    });

    test('returns Failure on DioException', () async {
      when(() => mockApiClient.getListing('bad-id')).thenThrow(
        makeDioException(statusCode: 404),
      );

      final result = await repository.getListing('bad-id');

      expect(result.isFailure, true);
    });
  });

  // =========================================================================
  // GROUP: delete
  // =========================================================================
  group('delete', () {
    test('returns Success on valid deletion', () async {
      when(() => mockApiClient.delete('listing-1')).thenAnswer(
        (_) async => const ApiResponse<void>(status: true, message: 'deleted'),
      );

      final result = await repository.delete('listing-1');

      expect(result.isSuccess, true);
    });

    test('returns Failure on API error', () async {
      when(() => mockApiClient.delete('listing-1')).thenAnswer(
        (_) async => const ApiResponse<void>(
          status: false,
          message: 'Not found',
        ),
      );

      final result = await repository.delete('listing-1');

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Not found');
      }
    });
  });

  // =========================================================================
  // GROUP: reserve / unreserve / markAsSold
  // =========================================================================
  group('reserve', () {
    test('returns Success with updated Listing', () async {
      final listing = makeListing(status: ListingStatus.reserved);
      when(() => mockApiClient.reserve('listing-1')).thenAnswer(
        (_) async => ApiResponse<Listing>(
          status: true,
          message: 'ok',
          data: listing,
        ),
      );

      final result = await repository.reserve('listing-1');

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.status, ListingStatus.reserved);
      }
    });
  });

  group('unreserve', () {
    test('returns Success with updated Listing', () async {
      final listing = makeListing();
      when(() => mockApiClient.unreserve('listing-1')).thenAnswer(
        (_) async => ApiResponse<Listing>(
          status: true,
          message: 'ok',
          data: listing,
        ),
      );

      final result = await repository.unreserve('listing-1');

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.status, ListingStatus.active);
      }
    });
  });

  group('markAsSold', () {
    test('returns Success with updated Listing', () async {
      final listing = makeListing(status: ListingStatus.sold);
      when(() => mockApiClient.markSold('listing-1')).thenAnswer(
        (_) async => ApiResponse<Listing>(
          status: true,
          message: 'ok',
          data: listing,
        ),
      );

      final result = await repository.markAsSold('listing-1');

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.status, ListingStatus.sold);
      }
    });
  });

  // =========================================================================
  // GROUP: Logging
  // =========================================================================
  group('Logging', () {
    test('logs DioException errors for debugging', () async {
      when(
        () => mockApiClient.getList(
          q: any(named: 'q'),
          categoryId: any(named: 'categoryId'),
          minPrice: any(named: 'minPrice'),
          maxPrice: any(named: 'maxPrice'),
          status: any(named: 'status'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      await repository.list(const ListListingsQuery());

      verify(
        () => mockLogger.e(
          '[ListingsRepository] list failed',
          error: any(named: 'error'),
        ),
      ).called(1);
    });

    test('logs unexpected errors for debugging', () async {
      when(() => mockApiClient.create(any())).thenThrow(
        Exception('unexpected'),
      );

      await repository.create(
        const CreateListingRequest(
          title: 'x',
          condition: Condition.isNew,
          categoryId: 1,
        ),
      );

      verify(
        () => mockLogger.e(
          '[ListingsRepository] create unexpected error',
          error: any(named: 'error'),
        ),
      ).called(1);
    });
  });
}
