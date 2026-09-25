import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_items_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// Page-scoped ViewModel driving SAVED ITEMS (profile menu).
///
/// The backend hydrates each saved bookmark with a full listing summary
/// (title, price, status, photos), so one request fills the grid —
/// listings that were deleted drop out server-side via the JOIN.
class SavedItemsViewModel implements Disposable {
  SavedItemsViewModel(this._savedItems);

  final SavedItemsRepository _savedItems;

  final Signal<List<ListingSummary>> listings = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  bool _disposed = false;

  Future<void> _fetch() async {
    isLoading.value = true;
    error.value = null;

    final result = await _savedItems.load();
    if (_disposed) return;

    switch (result) {
      case Success(:final value):
        listings.value = value;
      case Failure(:final message):
        error.value = message;
    }

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
