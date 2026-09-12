import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// Page-scoped ViewModel that drives the paginated listings feed.
///
/// A new instance is created per page visit via a GetIt scope; calling
/// [dispose] tears down every signal owned by this ViewModel.
class ListingsViewModel implements Disposable {
  ListingsViewModel(this._repository) {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;
      _cursor = null;
      hasMore.value = true;

      final result = await _repository.list(
        ListListingsQuery(
          q: query.value.isEmpty ? null : query.value,
          categoryId: categoryId.value,
        ),
      );

      switch (result) {
        case Success(:final value):
          listings.value = value.listings;
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });

    loadMore = action0(() async {
      if (isLoadingMore.value || !hasMore.value || _cursor == null) return;

      isLoadingMore.value = true;
      error.value = null;

      final result = await _repository.list(
        ListListingsQuery(
          q: query.value.isEmpty ? null : query.value,
          categoryId: categoryId.value,
          cursor: _cursor,
        ),
      );

      switch (result) {
        case Success(:final value):
          listings.value = [...listings.value, ...value.listings];
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoadingMore.value = false;
    });

    refresh = action0(() async {
      _cursor = null;
      hasMore.value = true;

      final result = await _repository.list(
        ListListingsQuery(
          q: query.value.isEmpty ? null : query.value,
          categoryId: categoryId.value,
        ),
      );

      switch (result) {
        case Success(:final value):
          listings.value = value.listings;
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }
    });
  }

  final ListingsRepository _repository;

  final Signal<List<ListingSummary>> listings = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isLoadingMore = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> hasMore = signal(true);

  String? _cursor;

  /// Current search / filter query, exposed so the UI can bind to it.
  final Signal<String> query = signal('');
  final Signal<int?> categoryId = signal(null);

  /// Fetches the first page of listings, replacing any existing data.
  late final void Function() fetch;

  /// Appends the next page to the existing list.
  late final void Function() loadMore;

  /// Resets the cursor and fetches fresh data (pull-to-refresh).
  late final void Function() refresh;

  void reset() {
    listings.value = [];
    isLoading.value = false;
    isLoadingMore.value = false;
    error.value = null;
    hasMore.value = true;
    _cursor = null;
    query.value = '';
    categoryId.value = null;
  }

  void dispose() {
    listings.dispose();
    isLoading.dispose();
    isLoadingMore.dispose();
    error.dispose();
    hasMore.dispose();
    query.dispose();
    categoryId.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
