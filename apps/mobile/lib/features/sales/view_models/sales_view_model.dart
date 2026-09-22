import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/sales/data/sales_repository.dart';
import 'package:uni_stash_mobile/features/sales/models/models.dart';
import 'package:uni_stash_mobile/features/sales/models/sales_dto.dart';

/// Which sale history a [SalesViewModel] loads.
enum SalesKind { purchases, sales }

/// Page-scoped ViewModel for the sale-history screens (guide 6.9/6.10).
///
/// One instance per page visit (registered in the page's GetIt scope)
/// handles cursor pagination for either history:
/// - [SalesKind.purchases] → `GET /sales/purchases` (My Purchases)
/// - [SalesKind.sales]     → `GET /sales/mine`      (My Sales)
///
/// The pages only read signals and call [fetch]/[loadMore] — all
/// repository access stays here in the application layer.
class SalesViewModel implements Disposable {
  SalesViewModel(this._repository, {required this.kind}) {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;
      _cursor = null;
      hasMore.value = true;

      final result = await _load(cursor: null);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          sales.value = value.sales;
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
          sales.value = [...sales.value, ...value.sales];
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoadingMore.value = false;
    });
  }

  final SalesRepository _repository;

  /// Which history this instance loads.
  final SalesKind kind;

  final Signal<List<Sale>> sales = signal([]);
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

  Future<Result<SalesListResponse>> _load({required String? cursor}) {
    return switch (kind) {
      SalesKind.purchases => _repository.myPurchases(cursor: cursor),
      SalesKind.sales => _repository.mySales(cursor: cursor),
    };
  }

  void reset() {
    sales.value = [];
    isLoading.value = false;
    isLoadingMore.value = false;
    error.value = null;
    hasMore.value = true;
    _cursor = null;
  }

  void dispose() {
    _disposed = true;
    sales.dispose();
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
