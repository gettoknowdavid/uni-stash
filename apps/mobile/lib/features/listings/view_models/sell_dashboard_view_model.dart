import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/sales/data/sales_repository.dart';
import 'package:uni_stash_mobile/features/sales/models/models.dart';

/// ViewModel for the SELL tab's dashboard: a session-lived summary of the
/// signed-in seller's storefront — headline stats (active listings, items
/// sold, total earnings), the listings currently needing attention
/// (reserved → awaiting handover), and recent activity.
///
/// Registered in DI like `ListingsViewModel` (the shell branch lives for
/// the whole session), refreshed whenever the tab becomes visible.
class SellDashboardViewModel implements Disposable {
  SellDashboardViewModel(
    this._listingsRepository,
    this._salesRepository, {
    required this.sellerId,
  }) {
    refresh = action0(() async {
      isLoading.value = true;
      error.value = null;
      await Future.wait([_loadListings(), _loadSales()]);
      if (_disposed) return;
      _computeStats();
      isLoading.value = false;
    });
  }

  final ListingsRepository _listingsRepository;
  final SalesRepository _salesRepository;

  /// The signed-in user's id — the `seller` filter for the listings API.
  final String sellerId;

  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  /// The seller's listings (first page, newest first).
  final Signal<List<ListingSummary>> listings = signal([]);

  /// The seller's recent sales (first page, newest first).
  final Signal<List<Sale>> sales = signal([]);

  /// Listings currently reserved — the "needs attention" strip: the
  /// handover hasn't happened yet, so these are the actionable ones.
  final Signal<List<ListingSummary>> reserved = signal([]);

  /// Headline numbers computed from the loaded pages.
  final Signal<int> activeCount = signal(0);
  final Signal<int> soldCount = signal(0);
  final Signal<int> earningsMinor = signal(0);

  bool _disposed = false;

  late final void Function() refresh;

  Future<void> _loadListings() async {
    final result = await _listingsRepository.listBySeller(sellerId);
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        listings.value = value.listings;
      case Failure(:final message):
        error.value = message;
    }
  }

  Future<void> _loadSales() async {
    final result = await _salesRepository.mySales();
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        sales.value = value.sales;
      case Failure():
        // Sales are supplementary to the dashboard; a failure here is
        // non-fatal — the listings stats still render.
    }
  }

  void _computeStats() {
    reserved.value = listings.value
        .where((l) => l.status == ListingStatus.reserved)
        .toList(growable: false);
    activeCount.value = listings.value
        .where((l) => l.status == ListingStatus.active)
        .length;
    soldCount.value = sales.value.length;
    earningsMinor.value = sales.value.fold(0, (sum, sale) {
      final price = sale.price;
      if (price == null) return sum;
      return sum + price.round();
    });
  }

  /// Called when the SELL tab becomes visible; refreshes only after the
  /// first load so tab-switching within a session isn't chatty.
  void onTabShown() {
    if (_hasLoaded) {
      refresh();
    } else {
      _hasLoaded = true;
      refresh();
    }
  }

  bool _hasLoaded = false;

  /// The signed-in user's id, resolved once for DI construction.
  static String currentUserId() =>
      di<UserViewModel>().currentUser.value?.id ?? '';

  void dispose() {
    _disposed = true;
    isLoading.dispose();
    error.dispose();
    listings.dispose();
    sales.dispose();
    reserved.dispose();
    activeCount.dispose();
    soldCount.dispose();
    earningsMinor.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
