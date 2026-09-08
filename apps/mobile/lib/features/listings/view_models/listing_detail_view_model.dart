import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';

/// Page-scoped ViewModel for a single listing's detail view.
///
/// Drives fetching, reserving, un-reserving and marking-as-sold actions.
class ListingDetailViewModel implements Disposable {
  ListingDetailViewModel(this._repository) {
    _init();
  }

  final ListingsRepository _repository;

  final Signal<ListingDetailResponse?> detail = signal(null);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  late final void Function(String id) fetch;
  late final void Function(String id) reserve;
  late final void Function(String id) unreserve;
  late final void Function(String id) markAsSold;

  /// Core fetch logic, awaited by [reserve]/[unreserve]/[markAsSold].
  Future<void> _fetch(String id) async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.getListing(id);
    switch (result) {
      case Success(:final value):
        detail.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isLoading.value = false;
  }

  void _init() {
    fetch = action1<String, void>((id) async {
      await _fetch(id);
    });

    reserve = action1<String, void>((id) async {
      error.value = null;

      final result = await _repository.reserve(id);
      switch (result) {
        case Success():
          await _fetch(id);
        case Failure(:final message):
          error.value = message;
      }
    });

    unreserve = action1<String, void>((id) async {
      error.value = null;

      final result = await _repository.unreserve(id);
      switch (result) {
        case Success():
          await _fetch(id);
        case Failure(:final message):
          error.value = message;
      }
    });

    markAsSold = action1<String, void>((id) async {
      error.value = null;

      final result = await _repository.markAsSold(id);
      switch (result) {
        case Success():
          await _fetch(id);
        case Failure(:final message):
          error.value = message;
      }
    });
  }

  void reset() {
    detail.value = null;
    isLoading.value = false;
    error.value = null;
  }

  void dispose() {
    detail.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
