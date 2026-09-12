import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/naira_currency_input_formatter.dart';

/// Page-scoped ViewModel that drives the listing editor (create flow).
///
/// Registered in a per-page GetIt scope (see `listing_editor.dart`), so every
/// visit gets a fresh instance that GetIt disposes when the scope pops.
class ListingEditorViewModel implements Disposable {
  ListingEditorViewModel(this._repository, this._categoriesRepository) {
    unawaited(loadCategories());
  }

  final ListingsRepository _repository;
  final CategoriesRepository _categoriesRepository;

  /// Categories for the picker, fetched from `GET /api/v1/categories`
  /// (CM-4.9). Empty until the fetch completes.
  final Signal<List<Category>> categories = signal(const []);

  /// Whether the initial categories fetch is still in flight.
  final Signal<bool> isLoadingCategories = signal(false);

  /// Set when categories fail to load; the UI offers a retry.
  final Signal<String?> categoriesError = signal(null);

  /// Mirrors the "BARTER ONLY, NO PRICE" switch. The switch itself is not a
  /// form field: this signal drives which conditional fields are mounted and
  /// decides how [submit] maps the form values into the request.
  final Signal<bool> barterOnly = signal(false);

  final Signal<bool> isSubmitting = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<Listing?> created = signal(null);

  /// Fetches the category list from the backend (public endpoint, no auth).
  /// Non-fatal on failure: the editor stays usable and the picker shows the
  /// retry state instead of blocking submission.
  Future<void> loadCategories() async {
    isLoadingCategories.value = true;
    categoriesError.value = null;

    final result = await _categoriesRepository.list();
    switch (result) {
      case Success(:final value):
        categories.value = value.categories;
      case Failure(:final message):
        categoriesError.value = message;
    }

    isLoadingCategories.value = false;
  }

  /// Submits a validated form-value map (`ShadFormState.value`).
  Future<void> submit(Map<String, dynamic> values) async {
    if (isSubmitting.value) return;

    final title = (values['title'] as String?)?.trim() ?? '';
    final description = (values['description'] as String?)?.trim() ?? '';
    final category = values['category'] as Category?;
    if (category == null) {
      error.value = 'Please select a category.';
      return;
    }
    final condition = values['condition'] as Condition?;
    final barterOnly = this.barterOnly.value;
    final priceText = values['price'] as String?;
    final barterRequest = (values['barter_request'] as String?)?.trim();

    // A listing is priced OR barter-only — mirrors the API's constraint.
    final request = CreateListingRequest(
      title: title,
      description: description,
      condition: condition ?? Condition.isNew,
      categoryId: category.id,
      price: barterOnly
          ? null
          : NairaCurrencyInputFormatter.parse(priceText ?? ''),
      barterRequest: barterOnly ? barterRequest : null,
    );

    di<Logger>().w(request.toJson());

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
    categories.dispose();
    isLoadingCategories.dispose();
    categoriesError.dispose();
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
