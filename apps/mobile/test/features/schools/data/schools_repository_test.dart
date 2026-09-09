import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_api.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';

class MockSchoolsApiClient extends Mock implements SchoolsApiClient {}

class MockLogger extends Mock implements Logger {}

School makeSchool({String id = 'school-1', String name = 'MIT'}) {
  return School(
    id: id,
    name: name,
    slug: name.toLowerCase(),
    domain: '${name.toLowerCase()}.edu',
    createdAt: DateTime(2025),
  );
}

DioException makeDioException({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? responseData,
}) {
  return DioException(
    type: type,
    requestOptions: RequestOptions(path: '/api/v1/schools'),
    response: (responseData != null || statusCode != null)
        ? Response(
            data: responseData,
            statusCode: statusCode,
            requestOptions: RequestOptions(path: '/api/v1/schools'),
          )
        : null,
  );
}

void main() {
  late MockSchoolsApiClient mockApiClient;
  late MockLogger mockLogger;
  late SchoolsRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(const ListSchoolsQuery());
  });

  setUp(() {
    mockApiClient = MockSchoolsApiClient();
    mockLogger = MockLogger();
    repository = SchoolsRepositoryImpl(mockApiClient, mockLogger);
  });

  group('list', () {
    test('returns Success with ListSchoolsResponse', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenAnswer(
        (_) async => ApiResponse<ListSchoolsResponse>(
          status: true,
          message: 'ok',
          data: ListSchoolsResponse(
            schools: [makeSchool()],
            nextCursor: 'cursor-abc',
          ),
        ),
      );

      final result = await repository.list(const ListSchoolsQuery(q: 'mit'));

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.schools.length, 1);
        expect(value.nextCursor, 'cursor-abc');
      }
    });

    test('passes query parameters to API client', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenAnswer(
        (_) async => const ApiResponse<ListSchoolsResponse>(
          status: true,
          message: 'ok',
          data: ListSchoolsResponse(schools: []),
        ),
      );

      await repository.list(const ListSchoolsQuery(
        q: 'stanford',
        cursor: 'prev-cursor',
        limit: 20,
      ));

      verify(() => mockApiClient.getList(
            q: 'stanford',
            cursor: 'prev-cursor',
            limit: 20,
          )).called(1);
    });

    test('returns Failure when API status is false', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenAnswer(
        (_) async => const ApiResponse<ListSchoolsResponse>(
          status: false,
          message: 'Server error',
        ),
      );

      final result = await repository.list(const ListSchoolsQuery());

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Server error');
      }
    });

    test('returns Failure on DioException', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      final result = await repository.list(const ListSchoolsQuery());

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, contains('internet connection'));
      }
    });

    test('returns generic failure on unexpected error', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenThrow(Exception('kaboom'));

      final result = await repository.list(const ListSchoolsQuery());

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'An unexpected error occurred.');
      }
    });
  });

  group('getSchool', () {
    test('returns Success with School', () async {
      final school = makeSchool();
      when(() => mockApiClient.getSchool('school-1')).thenAnswer(
        (_) async => ApiResponse<School>(
          status: true,
          message: 'ok',
          data: school,
        ),
      );

      final result = await repository.getSchool('school-1');

      expect(result.isSuccess, true);
      if (result case Success(:final value)) {
        expect(value.name, 'MIT');
      }
    });

    test('returns Failure when API status is false', () async {
      when(() => mockApiClient.getSchool('bad-id')).thenAnswer(
        (_) async => const ApiResponse<School>(
          status: false,
          message: 'Not found',
        ),
      );

      final result = await repository.getSchool('bad-id');

      expect(result.isFailure, true);
      if (result case Failure(:final message)) {
        expect(message, 'Not found');
      }
    });

    test('returns Failure on DioException', () async {
      when(() => mockApiClient.getSchool('school-1')).thenThrow(
        makeDioException(statusCode: 404),
      );

      final result = await repository.getSchool('school-1');

      expect(result.isFailure, true);
    });
  });

  group('Logging', () {
    test('logs DioException errors', () async {
      when(() => mockApiClient.getList(
            q: any(named: 'q'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenThrow(
        makeDioException(type: DioExceptionType.connectionError),
      );

      await repository.list(const ListSchoolsQuery());

      verify(
        () => mockLogger.e(
          '[SchoolsRepository] list failed',
          error: any(named: 'error'),
        ),
      ).called(1);
    });

    test('logs unexpected errors', () async {
      when(() => mockApiClient.getSchool(any())).thenThrow(
        Exception('unexpected'),
      );

      await repository.getSchool('school-1');

      verify(
        () => mockLogger.e(
          '[SchoolsRepository] getSchool unexpected error',
          error: any(named: 'error'),
        ),
      ).called(1);
    });
  });
}
