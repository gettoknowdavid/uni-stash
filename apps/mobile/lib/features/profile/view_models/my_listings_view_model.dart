import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
/// Page-scoped ViewModel driving MY LISTINGS (profile menu): every listing
/// the signed-in user owns, regardless of status (active, reserved, sold,
/// deleted), cursor-paginated like the browse feed.
class MyListingsViewModel implements Disposable {
  MyListingsViewModel(this._repository, {required this.sellerId}) {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;
      _cursor = null;
      hasMore.value = true;

      final result = await _load(cursor: null);
      if (_disposed) return;

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
      if (isLoading.value || isLoadingMore.value || !hasMore.value) return;

      isLoadingMore.value = true;
      error.value = null;

      final result = await _load(cursor: _cursor);
      if (_disposed) return;

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
  }

  final ListingsRepository _repository;

  /// The signed-in user's id — the `seller` filter for the listings API.
  final String sellerId;

  final Signal<List<ListingSummary>> listings = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isLoadingMore = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> hasMore = signal(true);

  bool _disposed = false;
  String? _cursor;

  /// Fetches the first page, replacing any existing data.
  late final void Function() fetch;

  /// Appends the next cursor page to the existing list.
  late final void Function() loadMore;

  Future<Result<ListListingsResponse>> _load({required String? cursor}) {
    return _repository.listBySeller(sellerId, cursor: cursor);
  }

  /// Re-runs the first fetch (pull-to-refresh / return from detail changes).
  void refresh() => fetch();

  void dispose() {
    _disposed = true;
    listings.dispose();
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
