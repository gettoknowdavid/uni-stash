import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/images/data/images_repository.dart';
import 'package:uni_stash_mobile/features/images/models/images_dto.dart';
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
  ListingEditorViewModel(
    this._repository,
    this._categoriesRepository,
    this._logger, {
    ImagesRepository? imagesRepository,
  }) : _imagesRepository = imagesRepository ?? di<ImagesRepository>() {
    unawaited(loadCategories());
  }

  final ListingsRepository _repository;
  final CategoriesRepository _categoriesRepository;
  final ImagesRepository _imagesRepository;
  final Logger _logger;

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

  /// Progress label while photos are being uploaded ("Uploading photo 1 of
  /// 3…"), null when idle. Surfaces real upload progress in the submit
  /// button instead of an unbounded spinner.
  final Signal<String?> uploadProgress = signal(null);

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
  ///
  /// Order of operations: create the listing first (photos presign against a
  /// real listing id), then upload each picked photo presign → PUT →
  /// confirm. A failed upload fails the submit with a clear message; the
  /// listing already exists, so re-submitting would duplicate it — the user
  /// cancels out instead.
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

    isSubmitting.value = true;
    error.value = null;

    final result = await _repository.create(request);

    switch (result) {
      case Success(:final value):
        final uploadError = await _uploadPhotos(
          value.id,
          values['photos'] as List<ListingImage>?,
        );
        if (uploadError != null) {
          error.value = uploadError;
          isSubmitting.value = false;
          return;
        }
        created.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isSubmitting.value = false;
  }

  /// Uploads every picked photo to the freshly-created listing. Returns a
  /// human-readable message on the first failure, null when all uploads
  /// succeeded (or there was nothing to upload).
  Future<String?> _uploadPhotos(
    String listingId,
    List<ListingImage>? photos,
  ) async {
    final picked =
        photos?.whereType<LocalImage>().toList() ?? const <LocalImage>[];
    if (picked.isEmpty) return null;

    for (var i = 0; i < picked.length; i++) {
      final photo = picked[i];
      uploadProgress.value = 'Uploading photo ${i + 1} of ${picked.length}…';
      final contentType = ImageContentType.fromPath(photo.localPath);
      final result = await _imagesRepository.upload(
        listingId,
        ImageUpload(path: photo.localPath, contentType: contentType),
      );
      switch (result) {
        case Success():
          break;
        case Failure(:final message):
          _logger.e(
            '[ListingEditorViewModel] photo upload failed '
            '(${i + 1}/${picked.length}): $message',
          );
          uploadProgress.value = null;
          return 'Your listing was created but photo ${i + 1} failed to '
              'upload: $message';
      }
    }

    uploadProgress.value = null;
    return null;
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
    uploadProgress.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
