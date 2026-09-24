import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_api.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_dto.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_repository.dart';

class _MockClient extends Mock implements SavedItemsApiClient {}

void main() {
  late _MockClient client;
  late SavedItemsRepositoryImpl repo;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0);
  });

  setUp(() {
    client = _MockClient();
    repo = SavedItemsRepositoryImpl(client, Logger(level: Level.off));
  });

  SavedItem item(String id) => SavedItem(
        listingId: id,
        savedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

  ApiResponse<SavedItemsListResponse> okList(List<SavedItem> items) =>
      ApiResponse(
        status: true,
        message: 'ok',
        data: SavedItemsListResponse(items: items),
      );

  ApiResponse<SavedItemStatusResponse> status({required bool saved}) =>
      ApiResponse(
        status: true,
        message: 'ok',
        data: SavedItemStatusResponse(saved: saved),
      );

  HttpResponse<void> noContent() => HttpResponse<void>(
        null,
        Response<void>(
          requestOptions: RequestOptions(path: '/api/v1/saved-items/x'),
          statusCode: 204,
        ),
      );

  test('load maps listing ids, newest first', () async {
    when(() => client.list(cursor: any(named: 'cursor'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => okList([item('b'), item('a')]));

    final result = await repo.load();
    expect(result, isA<Success<List<String>>>());
    expect((result as Success<List<String>>).value, ['b', 'a']);
  });

  test('load failure surfaces message', () async {
    when(() => client.list(cursor: any(named: 'cursor'),
            limit: any(named: 'limit')))
        .thenAnswer(
      (_) async => const ApiResponse(status: false, message: 'boom'),
    );
    final result = await repo.load();
    expect(result, isA<Failure<List<String>>>());
    expect((result as Failure<List<String>>).message, 'boom');
  });

  test('save maps success', () async {
    when(() => client.save('x')).thenAnswer(
      (_) async => const ApiResponse(status: true, message: 'saved'),
    );
    final result = await repo.save('x');
    expect(result, isA<Success<void>>());
  });

  test('remove treats 2xx (204 No Content) as success', () async {
    when(() => client.unsave('x')).thenAnswer((_) async => noContent());
    final result = await repo.remove('x');
    expect(result, isA<Success<void>>());
  });

  test('remove surfaces non-2xx as failure', () async {
    when(() => client.unsave('x')).thenAnswer(
      (_) async => HttpResponse<void>(
        null,
        Response<void>(
          requestOptions: RequestOptions(path: '/api/v1/saved-items/x'),
          statusCode: 500,
        ),
      ),
    );
    final result = await repo.remove('x');
    expect(result, isA<Failure<void>>());
  });

  test('isSaved maps the status endpoint', () async {
    when(() => client.status('x'))
        .thenAnswer((_) async => status(saved: true));
    final result = await repo.isSaved('x');
    expect(result, isA<Success<bool>>());
    expect((result as Success<bool>).value, isTrue);
  });

  test('toggle unsaves when saved and saves when not', () async {
    when(() => client.status('x'))
        .thenAnswer((_) async => status(saved: true));
    when(() => client.unsave('x')).thenAnswer((_) async => noContent());

    final removed = await repo.toggle('x');
    expect(removed, isA<Success<bool>>());
    expect((removed as Success<bool>).value, isFalse);

    when(() => client.status('x'))
        .thenAnswer((_) async => status(saved: false));
    when(() => client.save('x')).thenAnswer(
      (_) async => const ApiResponse(status: true, message: 'saved'),
    );

    final added = await repo.toggle('x');
    expect(added, isA<Success<bool>>());
    expect((added as Success<bool>).value, isTrue);
  });
}
