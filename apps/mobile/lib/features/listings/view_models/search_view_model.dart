import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/search_history_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// ViewModel driving the SEARCH tab (guide: `GET /api/v1/listings?q=…`
/// full-text search layered on the browse filters).
///
/// Responsibilities:
/// * debounced live search as the user types (see [onQueryChanged]);
/// * category + price-range filters that combine with the query;
/// * cursor pagination — note the backend drops the cursor for ranked
///   search results (no `next_cursor`), so [hasMore] simply goes false
///   there while browse-style (no `q`) fetches keep paginating;
/// * the recent-searches list, persisted via [SearchHistoryRepository].
///
/// Registered as a lazy singleton in the authenticated scope alongside
/// `ListingsViewModel` — the SEARCH shell branch lives for the whole
/// session, so its state should too.
class SearchViewModel implements Disposable {
  SearchViewModel(
    this._repository,
    this._categoriesRepository,
    this._history, {
    Duration debounce = const Duration(milliseconds: 350),
  }) : _debounce = debounce {
    loadCategories = action0(() async {
      if (_disposed) return;
      final result = await _categoriesRepository.list();
      if (_disposed) return;
      if (result case Success(value: final response)) {
        categories.value = response.categories;
      }
    });
  }

  final ListingsRepository _repository;
  final CategoriesRepository _categoriesRepository;
  final SearchHistoryRepository _history;
  final Duration _debounce;

  /// Current text query, bound to the search field.
  final Signal<String> query = signal('');

  /// Category filter (null = ALL).
  final Signal<int?> categoryId = signal(null);

  /// Price bounds in minor units (kobo), matching `ListListingsQuery`.
  final Signal<int?> minPrice = signal(null);
  final Signal<int?> maxPrice = signal(null);

  final Signal<List<ListingSummary>> results = signal(const []);
  final Signal<List<Category>> categories = signal(const []);
  final Signal<List<String>> recentSearches = signal(const []);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isLoadingMore = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> hasMore = signal(true);

  late final void Function() loadCategories;

  Timer? _debounceTimer;
  String? _cursor;
  int _requestSeq = 0;
  bool _disposed = false;

  /// Whether any search criterion (text, category, price) is set. When
  /// false the page shows the idle state (recent searches) instead of
  /// results — browsing the whole catalogue is the Home tab's job.
  bool get hasCriteria =>
      query.value.trim().isNotEmpty ||
      categoryId.value != null ||
      minPrice.value != null ||
      maxPrice.value != null;

  bool get hasPriceFilter => minPrice.value != null || maxPrice.value != null;

  /// Called on every keystroke: updates [query] and re-runs the search
  /// after a short pause. Clearing the query back to no criteria at all
  /// returns to the idle state immediately (no pointless browse fetch).
  void onQueryChanged(String value) {
    query.value = value;
    _debounceTimer?.cancel();
    if (!hasCriteria) {
      _resetToIdle();
      return;
    }
    _debounceTimer = Timer(_debounce, search);
  }

  /// Called on submit (keyboard search action): skips the debounce and
  /// records the term in the recent-searches history.
  void submitSearch() {
    _debounceTimer?.cancel();
    final term = query.value.trim();
    if (term.isNotEmpty) unawaited(_remember(term));
    if (!hasCriteria) {
      _resetToIdle();
      return;
    }
    unawaited(search());
  }

  /// Re-runs a saved term from the recent-searches list.
  void applyRecentSearch(String term) {
    query.value = term;
    _debounceTimer?.cancel();
    unawaited(_remember(term));
    unawaited(search());
  }

  Future<void> _remember(String term) async {
    try {
      final updated = await _history.add(term);
      if (!_disposed) recentSearches.value = updated;
    } on Object {
      // History is best-effort; never block the search on it.
    }
  }

  Future<void> loadRecentSearches() async {
    final entries = await _history.load();
    if (!_disposed) recentSearches.value = entries;
  }

  Future<void> clearRecentSearches() async {
    recentSearches.value = const [];
    await _history.clear();
  }

  void setCategory(int? id) {
    if (categoryId.value == id) return;
    categoryId.value = id;
    _applyCriteriaChange();
  }

  /// Price bounds in kobo; either side may be null (unbounded).
  void setPriceRange({int? min, int? max}) {
    minPrice.value = min;
    maxPrice.value = max;
    _applyCriteriaChange();
  }

  void clearFilters() {
    categoryId.value = null;
    minPrice.value = null;
    maxPrice.value = null;
    _applyCriteriaChange();
  }

  void _applyCriteriaChange() {
    _debounceTimer?.cancel();
    if (!hasCriteria) {
      _resetToIdle();
      return;
    }
    unawaited(search());
  }

  /// Fetches the first page with the current criteria, replacing results.
  Future<void> search() => _run(showLoading: true);

  /// Same as [search] but keeps the current results on screen while the
  /// request is in flight (pull-to-refresh shouldn't blank the grid).
  Future<void> refresh() => _run(showLoading: false);

  /// Appends the next cursor page. No-op while a page is loading, when
  /// there is no more (ranked search results never paginate), or when the
  /// user has no criteria set.
  Future<void> loadMore() async {
    if (isLoadingMore.value ||
        isLoading.value ||
        !hasMore.value ||
        _cursor == null ||
        !hasCriteria) {
      return;
    }
    await _run(showLoading: false, append: true);
  }

  Future<void> _run({
    required bool showLoading,
    bool append = false,
  }) async {
    // Sequence token: a newer run invalidates in-flight older ones, so a
    // slow response can't clobber the results of a newer query.
    final seq = ++_requestSeq;
    if (showLoading) isLoading.value = true;
    if (append) isLoadingMore.value = true;
    error.value = null;

    final trimmed = query.value.trim();
    final result = await _repository.list(
      ListListingsQuery(
        q: trimmed.isEmpty ? null : trimmed,
        categoryId: categoryId.value,
        minPrice: minPrice.value,
        maxPrice: maxPrice.value,
        cursor: append ? _cursor : null,
      ),
    );

    if (_disposed || seq != _requestSeq) return;

    switch (result) {
      case Success(:final value):
        results.value = append
            ? [...results.value, ...value.listings]
            : value.listings;
        _cursor = value.nextCursor;
        hasMore.value = value.nextCursor != null;
      case Failure(:final message):
        // Keep whatever is on screen; only surface the error when we have
        // nothing to show for it.
        if (results.value.isEmpty || !append) error.value = message;
    }

    isLoading.value = false;
    isLoadingMore.value = false;
  }

  /// Back to the idle state: no criteria, no results, no pending request.
  void _resetToIdle() {
    _requestSeq++;
    _cursor = null;
    results.value = const [];
    error.value = null;
    isLoading.value = false;
    isLoadingMore.value = false;
    hasMore.value = true;
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    query.dispose();
    categoryId.dispose();
    minPrice.dispose();
    maxPrice.dispose();
    results.dispose();
    categories.dispose();
    recentSearches.dispose();
    isLoading.dispose();
    isLoadingMore.dispose();
    error.dispose();
    hasMore.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
