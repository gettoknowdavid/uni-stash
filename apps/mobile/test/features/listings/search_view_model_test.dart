import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/search_history_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/search_view_model.dart';

class MockListingsRepository extends Mock implements ListingsRepository {}

class MockCategoriesRepository extends Mock implements CategoriesRepository {}

class MockSearchHistoryRepository extends Mock
    implements SearchHistoryRepository {}

ListingSummary buildSummary(String id, {String title = 'Item'}) {
  return ListingSummary(
    id: id,
    title: title,
    condition: Condition.used,
    status: ListingStatus.active,
    createdAt: DateTime(2026),
  );
}

ListListingsResponse page(
  List<ListingSummary> listings, {
  String? nextCursor,
}) => ListListingsResponse(listings: listings, nextCursor: nextCursor);

void main() {
  late MockListingsRepository listings;
  late MockCategoriesRepository categories;
  late MockSearchHistoryRepository history;
  late SearchViewModel model;

  /// Recorded `ListListingsQuery` arguments, one per repository call.
  final queries = <ListListingsQuery>[];

  setUpAll(() {
    registerFallbackValue(const ListListingsQuery());
  });

  setUp(() {
    listings = MockListingsRepository();
    categories = MockCategoriesRepository();
    history = MockSearchHistoryRepository();
    queries.clear();
    when(history.load).thenAnswer((_) async => const <String>[]);
    when(() => history.add(any())).thenAnswer((_) async => const <String>[]);
    model = SearchViewModel(
      listings,
      categories,
      history,
      debounce: const Duration(milliseconds: 10),
    );
  });

  tearDown(() => model.dispose());

  // Records the query of every `list` call by capturing it once per call.
  void stubWithCapture(Result<ListListingsResponse> result) {
    when(() => listings.list(any())).thenAnswer((invocation) async {
      queries.add(
        invocation.positionalArguments.first as ListListingsQuery,
      );
      return result;
    });
  }

  test('idle by default: no fetch until criteria are set', () async {
    expect(model.hasCriteria, isFalse);
    await model.loadMore();
    verifyNever(() => listings.list(any()));
    expect(model.results.value, isEmpty);
  });

  group('onQueryChanged', () {
    test('debounces keystrokes into a single fetch', () async {
      stubWithCapture(
        Result.success(page([buildSummary('l1')])),
      );

      model.onQueryChanged('mi');
      model.onQueryChanged('mini');
      model.onQueryChanged('mini frid');
      expect(model.isLoading.value, isFalse); // not fetched yet

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();

      expect(queries, hasLength(1));
      expect(queries.single.q, 'mini frid');
      expect(model.results.value, hasLength(1));
      expect(model.isLoading.value, isFalse);
    });

    test('clearing the query returns to idle without fetching', () async {
      stubWithCapture(Result.success(page([buildSummary('l1')])));

      model.onQueryChanged('mini');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();
      expect(queries, hasLength(1));

      model.onQueryChanged('');
      await pumpEventQueue();

      expect(model.hasCriteria, isFalse);
      expect(model.results.value, isEmpty);
      expect(queries, hasLength(1)); // no extra browse fetch
    });

    test('submitSearch skips the debounce and records the term', () async {
      stubWithCapture(Result.success(page([buildSummary('l1')])));
      when(() => history.add('fridge')).thenAnswer(
        (_) async => const ['fridge'],
      );

      model.onQueryChanged('fridge');
      model.submitSearch();
      await pumpEventQueue();

      expect(queries, hasLength(1));
      verify(() => history.add('fridge')).called(1);
      expect(model.recentSearches.value, ['fridge']);
    });
  });

  group('filters', () {
    test('category and price bounds ride along in the query', () async {
      stubWithCapture(const Result.success(ListListingsResponse(listings: [])));

      model.onQueryChanged('tv');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      model.setCategory(7);
      await pumpEventQueue();
      model.setPriceRange(min: 1000, max: 500000);
      await pumpEventQueue();

      expect(queries, hasLength(3));
      expect(queries.last.q, 'tv');
      expect(queries.last.categoryId, 7);
      expect(queries.last.minPrice, 1000);
      expect(queries.last.maxPrice, 500000);
      expect(model.hasPriceFilter, isTrue);
    });

    test('clearing all filters returns to idle', () async {
      stubWithCapture(const Result.success(ListListingsResponse(listings: [])));

      model.setCategory(3);
      await pumpEventQueue();
      expect(model.hasCriteria, isTrue);

      model.clearFilters();
      await pumpEventQueue();

      expect(model.hasCriteria, isFalse);
      expect(model.results.value, isEmpty);
      expect(model.hasPriceFilter, isFalse);
    });
  });

  group('pagination', () {
    test('appends the cursor page until nextCursor runs out', () async {
      when(() => listings.list(any())).thenAnswer((invocation) async {
        queries.add(
          invocation.positionalArguments.first as ListListingsQuery,
        );
        // First page has a cursor; the second does not.
        return queries.length == 1
            ? Result.success(
                page([buildSummary('l1')], nextCursor: 'cur1'),
              )
            : Result.success(page([buildSummary('l2')]));
      });

      model.onQueryChanged('book');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();
      expect(model.hasMore.value, isTrue);

      await model.loadMore();
      expect(model.results.value.map((r) => r.id), ['l1', 'l2']);
      expect(queries, hasLength(2));
      expect(queries.last.cursor, 'cur1');

      // No cursor now — further loadMore calls are no-ops.
      await model.loadMore();
      expect(queries, hasLength(2));
      expect(model.hasMore.value, isFalse);
    });

    test('a failed fetch surfaces the error', () async {
      when(() => listings.list(any())).thenAnswer(
        (_) async => const Result.failure('network down'),
      );

      model.onQueryChanged('x');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();

      expect(model.error.value, 'network down');
      expect(model.isLoading.value, isFalse);
    });

    test('a stale response cannot clobber a newer search', () async {
      var calls = 0;
      when(() => listings.list(any())).thenAnswer((invocation) async {
        final query =
            invocation.positionalArguments.first as ListListingsQuery;
        calls++;
        if (calls == 1) {
          // First (older) request: slow.
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return Result.success(page([buildSummary('id-${query.q}')]));
      });

      model.onQueryChanged('old');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      model.onQueryChanged('new');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();

      // The final results must come from the 'new' query, not the stale one.
      expect(model.results.value.single.id, contains('new'));
    });
  });

  group('recent searches', () {
    test('applyRecentSearch sets the query, records it and fetches', () async {
      stubWithCapture(Result.success(page([buildSummary('l1')])));
      when(() => history.add('fridge')).thenAnswer(
        (_) async => const ['fridge'],
      );

      model.applyRecentSearch('fridge');
      await pumpEventQueue();

      expect(model.query.value, 'fridge');
      expect(queries.single.q, 'fridge');
      verify(() => history.add('fridge')).called(1);
    });

    test('loadRecentSearches and clearRecentSearches round-trip', () async {
      when(history.load).thenAnswer(
        (_) async => const ['tv', 'book'],
      );
      when(history.clear).thenAnswer((_) async {});

      await model.loadRecentSearches();
      expect(model.recentSearches.value, ['tv', 'book']);

      await model.clearRecentSearches();
      expect(model.recentSearches.value, isEmpty);
      verify(history.clear).called(1);
    });
  });
}
