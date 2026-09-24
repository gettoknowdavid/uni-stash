import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// Page-scoped ViewModel driving SAVED ITEMS (profile menu).
///
/// Loads the user's bookmarked listing ids from the server, then resolves
/// each id with a listings detail fetch (best-effort, sequential — the
/// list is usually small). Listings that no longer resolve (deleted /
/// hidden by their owner) drop off the list automatically.
class SavedItemsViewModel implements Disposable {
  SavedItemsViewModel(this._repository, this._savedItems);

  final ListingsRepository _repository;
  final SavedItemsRepository _savedItems;

  final Signal<List<ListingSummary>> listings = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  bool _disposed = false;

  Future<void> _fetch() async {
    isLoading.value = true;
    error.value = null;

    final idsResult = await _savedItems.load();
    if (_disposed) return;

    final List<String> ids;
    switch (idsResult) {
      case Success(value: final idsLoaded):
        ids = idsLoaded;
      case Failure(:final message):
        error.value = message;
        isLoading.value = false;
        return;
    }

    final resolved = <ListingSummary>[];
    String? failure;
    for (final id in ids) {
      final result = await _repository.getListing(id);
      switch (result) {
        case Success(value: final detail?):
          resolved.add(
            ListingSummary(
              id: detail.id,
              title: detail.title,
              condition: detail.condition,
              status: detail.status,
              createdAt: detail.createdAt,
              price: detail.price,
              barterRequest: detail.barterRequest,
              images: detail.images,
            ),
          );
        case Failure(:final message):
          // 404-style misses just drop the stale bookmark; keep the first
          // real (transient) failure around for the empty state.
          failure ??= message;
        default:
          break;
      }
      if (_disposed) return;
    }

    listings.value = resolved;
    if (resolved.isEmpty && failure != null) error.value = failure;
    isLoading.value = false;
  }

  /// Fetches the saved listings, replacing any existing data.
  void fetch() {
    unawaited(_fetch());
  }

  void dispose() {
    _disposed = true;
    listings.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
