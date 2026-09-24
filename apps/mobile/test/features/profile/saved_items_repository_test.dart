import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_repository.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockStorage storage;
  late SavedItemsRepository repo;

  setUpAll(() {
    registerFallbackValue(<String, String>{});
  });

  setUp(() {
    storage = _MockStorage();
    repo = SavedItemsRepository(storage);
  });

  test('load returns empty list when nothing stored', () async {
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    expect(await repo.load(), isEmpty);
  });

  test('load returns corrupt payload as empty list', () async {
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'not json {');
    expect(await repo.load(), isEmpty);
  });

  test('add prepends and dedupes', () async {
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => '["a","b"]');
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});

    final updated = await repo.add('c');
    expect(updated, ['c', 'a', 'b']);

    final deduped = await repo.add('a');
    expect(deduped, ['a', 'b']);
  });

  test('remove drops the id', () async {
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => '["a","b"]');
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});

    expect(await repo.remove('a'), ['b']);
  });

  test('toggle saves unsaved and removes saved', () async {
    var stored = '["a"]';
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((inv) async {
      stored = inv.namedArguments[#value] as String;
    });
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => stored);

    final (removed, nowSaved) = await repo.toggle('a');
    expect(removed, isEmpty);
    expect(nowSaved, isFalse);

    final (added, saved) = await repo.toggle('a');
    expect(added, ['a']);
    expect(saved, isTrue);
  });
}
