import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/naira_currency_input_formatter.dart';

/// Page-scoped ViewModel that drives the listing editor (create flow).
///
/// Registered in a per-page GetIt scope (see `listing_editor.dart`), so every
/// visit gets a fresh instance that GetIt disposes when the scope pops.
class ListingEditorViewModel implements Disposable {
  ListingEditorViewModel(this._repository);

  final ListingsRepository _repository;

  /// Mirrors the "BARTER ONLY, NO PRICE" switch. The switch itself is not a
  /// form field: this signal drives which conditional fields are mounted and
  /// decides how [submit] maps the form values into the request.
  final Signal<bool> barterOnly = signal(false);

  final Signal<bool> isSubmitting = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<Listing?> created = signal(null);

  /// Submits a validated form-value map (`ShadFormState.value`).
  Future<void> submit(Map<String, dynamic> values) async {
    if (isSubmitting.value) return;

    final title = (values['title'] as String?)?.trim() ?? '';
    final description = (values['description'] as String?)?.trim() ?? '';
    final category = values['category'] as Category?;
    final condition = values['condition'] as Condition?;
    final barterOnly = this.barterOnly.value;
    final priceText = values['price'] as String?;
    final barterRequest = (values['barter_request'] as String?)?.trim();

    final request = CreateListingRequest(
      title: title,
      description: description,
      condition: condition ?? Condition.isNew,
      categoryId: category?.id ?? 0,
      price: barterOnly
          ? null
          : NairaCurrencyInputFormatter.parse(priceText ?? ''),
      barterRequest: barterOnly ? barterRequest : null,
    );

    isSubmitting.value = true;
    error.value = null;

    final result = await _repository.create(request);

    switch (result) {
      case Success(:final value):
        created.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isSubmitting.value = false;
  }

  /// Clears one-shot submit state after the UI has reacted to it.
  void consumeResult() {
    created.value = null;
    error.value = null;
  }

  void dispose() {
    barterOnly.dispose();
    isSubmitting.dispose();
    error.dispose();
    created.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
