import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_api.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

class MockCategoriesApiClient extends Mock implements CategoriesApiClient {}

class MockLogger extends Mock implements Logger {}

DioException makeDioException({int? statusCode}) {
  return DioException(
    type: DioExceptionType.badResponse,
    requestOptions: RequestOptions(path: '/api/v1/categories'),
    response: Response(
      data: <String, dynamic>{},
      statusCode: statusCode,
      requestOptions: RequestOptions(path: '/api/v1/categories'),
    ),
  );
}

void main() {
  late MockCategoriesApiClient mockApiClient;
  late MockLogger mockLogger;
  late CategoriesRepository repository;

  setUp(() {
    mockApiClient = MockCategoriesApiClient();
    mockLogger = MockLogger();
    repository = CategoriesRepositoryImpl(mockApiClient, mockLogger);
  });

  // =========================================================================
  // GROUP: list - Success
  // =========================================================================

  group('list - Success', () {
    test('returns categories on success', () async {
      const response = ApiResponse<ListCategoriesResponse>(
        status: true,
        message: 'ok',
        data: ListCategoriesResponse(
          categories: [
            Category(id: 1, slug: 'textbooks', label: 'Textbooks'),
            Category(id: 2, slug: 'electronics', label: 'Electronics'),
          ],
        ),
      );
      when(() => mockApiClient.getCategories())
          .thenAnswer((_) async => response);

      final result = await repository.list();

      expect(result, isA<Success<ListCategoriesResponse>>());
      final data = (result as Success<ListCategoriesResponse>).value;
      expect(data.categories, hasLength(2));
      expect(data.categories[0].slug, 'textbooks');
      expect(data.categories[1].label, 'Electronics');
      verify(() => mockApiClient.getCategories()).called(1);
    });

    test('returns empty list when backend has no categories', () async {
      const response = ApiResponse<ListCategoriesResponse>(
        status: true,
        message: 'ok',
        data: ListCategoriesResponse(categories: []),
      );
      when(() => mockApiClient.getCategories())
          .thenAnswer((_) async => response);

      final result = await repository.list();

      expect(result, isA<Success<ListCategoriesResponse>>());
      expect(
        (result as Success<ListCategoriesResponse>).value.categories,
        isEmpty,
      );
    });
  });

  // =========================================================================
  // GROUP: list - Failure
  // =========================================================================

  group('list - Failure', () {
    test('maps status:false envelope to failure', () async {
      const response = ApiResponse<ListCategoriesResponse>(
        status: false,
        message: 'something went wrong',
      );
      when(() => mockApiClient.getCategories())
          .thenAnswer((_) async => response);

      final result = await repository.list();

      expect(result, isA<Failure<ListCategoriesResponse>>());
      expect(
        (result as Failure<ListCategoriesResponse>).message,
        'something went wrong',
      );
    });

    test('maps null data to failure', () async {
      const response = ApiResponse<ListCategoriesResponse>(
        status: true,
        message: 'ok',
      );
      when(() => mockApiClient.getCategories())
          .thenAnswer((_) async => response);

      final result = await repository.list();

      expect(result, isA<Failure<ListCategoriesResponse>>());
      expect((result as Failure<ListCategoriesResponse>).message, 'No data');
    });

    test('maps DioException to human-readable failure', () async {
      when(() => mockApiClient.getCategories())
          .thenThrow(makeDioException(statusCode: 500));

      final result = await repository.list();

      expect(result, isA<Failure<ListCategoriesResponse>>());
      expect(
        (result as Failure<ListCategoriesResponse>).message,
        isNot('An unexpected error occurred.'),
      );
    });

    test('maps unexpected errors to generic failure', () async {
      when(() => mockApiClient.getCategories()).thenThrow(StateError('boom'));

      final result = await repository.list();

      expect(result, isA<Failure<ListCategoriesResponse>>());
      expect(
        (result as Failure<ListCategoriesResponse>).message,
        'An unexpected error occurred.',
      );
    });
  });
}
