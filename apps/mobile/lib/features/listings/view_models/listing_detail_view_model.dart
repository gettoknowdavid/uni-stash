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
  final Signal<bool> isDeleting = signal(false);

  /// Set to the deleted listing's id after a successful delete. The page
  /// reacts by navigating back; the view model cannot pop routes itself.
  final Signal<String?> deletedId = signal(null);

  /// Set when a delete fails. Separate from [error] so the page can toast
  /// deletion failures without also toasting fetch/reserve errors, which
  /// the page already surfaces inline.
  final Signal<String?> deleteError = signal(null);

  late final void Function(String id) fetch;
  late final void Function(String id) reserve;
  late final void Function(String id) unreserve;
  late final void Function(String id) markAsSold;
  late final void Function(String id) delete;

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

    delete = action1<String, void>((id) async {
      // Re-entrancy guard, set before the first await so a double-tap
      // cannot fire two DELETE requests.
      if (isDeleting.value) return;
      isDeleting.value = true;
      deleteError.value = null;

      final result = await _repository.delete(id);
      switch (result) {
        case Success():
          // `detail` is intentionally left as-is: the page pops straight
          // back on `deletedId`, so clearing it here would only flash the
          // "Listing not found" state for a frame.
          deletedId.value = id;
        case Failure(:final message):
          deleteError.value = message;
      }

      isDeleting.value = false;
    });
  }

  void reset() {
    detail.value = null;
    isLoading.value = false;
    error.value = null;
    isDeleting.value = false;
    deletedId.value = null;
    deleteError.value = null;
  }

  /// Clears one-shot delete state after the UI has reacted to it.
  void consumeDeleteResult() {
    deletedId.value = null;
    deleteError.value = null;
  }

  void dispose() {
    detail.dispose();
    isLoading.dispose();
    error.dispose();
    isDeleting.dispose();
    deletedId.dispose();
    deleteError.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
