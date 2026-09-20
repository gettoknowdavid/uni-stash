import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/images/data/images_repository.dart';
import 'package:uni_stash_mobile/features/images/models/images_dto.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listing_draft_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_draft.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/naira_currency_input_formatter.dart';

/// Page-scoped ViewModel that drives the listing editor (create & edit flows).
///
/// Registered in a per-page GetIt scope (see `listing_editor.dart`), so every
/// visit gets a fresh instance that GetIt disposes when the scope pops.
class ListingEditorViewModel implements Disposable {
  ListingEditorViewModel(
    this._repository,
    this._categoriesRepository,
    this._logger, {
    ImagesRepository? imagesRepository,
    ListingDraftRepository? draftRepository,
  }) : _imagesRepository = imagesRepository ?? di<ImagesRepository>(),
       _draftRepository = draftRepository ?? di<ListingDraftRepository>() {
    unawaited(loadCategories());
  }

  final ListingsRepository _repository;
  final CategoriesRepository _categoriesRepository;
  final ImagesRepository _imagesRepository;
  final ListingDraftRepository _draftRepository;
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

  /// The listing being edited, or `null` when creating a new one.
  final Signal<ListingDetailResponse?> existingListing = signal(null);

  /// Whether we're in edit mode (vs create).
  bool get isEditMode => existingListing.value != null;

  final Signal<bool> isSubmitting = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<Listing?> created = signal(null);
  final Signal<bool> isUpdating = signal(false);

  /// Progress label while photos are being uploaded ("Uploading photo 1 of
  /// 3…"), null when idle. Surfaces real upload progress in the submit
  /// button instead of an unbounded spinner.
  final Signal<String?> uploadProgress = signal(null);

  /// When a listing is successfully created but photo uploads fail, the
  /// listing ID is saved here so the next [submit] call PATCHes the
  /// existing listing instead of creating a duplicate.
  String? _createdListingId;

  /// The most recently loaded draft, if any. The editor page reads this
  /// in `initState` to decide whether to show a "Resume draft?" prompt.
  ListingDraft? lastLoadedDraft;

  // ---------------------------------------------------------------------------
  // Draft persistence
  // ---------------------------------------------------------------------------

  /// Loads any saved draft from local storage. Call once in the editor's
  /// `initState`. Returns the draft (for the UI to offer a resume prompt) or
  /// `null` if there's nothing to resume.
  Future<ListingDraft?> loadDraft() async {
    final draft = await _draftRepository.load();
    lastLoadedDraft = draft;
    return draft;
  }

  /// Populates the ViewModel signals from a [draft] so the editor page can
  /// pre-fill its form fields.
  void applyDraft(ListingDraft draft) {
    _createdListingId = draft.listingId;
    barterOnly.value = draft.barterOnly;
  }

  /// Discards the saved draft without submitting. Called when the user taps
  /// "Start fresh" on the resume prompt.
  Future<void> discardDraft() async {
    lastLoadedDraft = null;
    await _draftRepository.clear();
  }

  /// Saves the current form state as a draft so it survives crashes.
  Future<void> _saveDraft({
    required String title,
    required String description,
    required int categoryId,
    required Condition condition,
    required bool barterOnly,
    required List<String> imagePaths,
    int? price,
    String? barterRequest,
  }) async {
    final draft = ListingDraft(
      title: title,
      description: description,
      categoryId: categoryId,
      condition: condition.name,
      price: price,
      barterRequest: barterRequest,
      barterOnly: barterOnly,
      imagePaths: imagePaths,
      listingId: _createdListingId,
    );
    await _draftRepository.save(draft);
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  /// Submits a validated form-value map (`ShadFormState.value`).
  ///
  /// Order of operations:
  /// 1. Persist a draft (so a crash doesn't lose state).
  /// 2. Create the listing (or PATCH an existing one on retry).
  /// 3. Upload each picked photo presign → PUT → confirm.
  /// 4. Clear the draft on full success.
  Future<void> submit(Map<String, dynamic> values) async {
    // Re-entrancy guard. `isSubmitting` must be set synchronously, before
    // the first `await`: a double-tap on PUBLISH delivers the second tap's
    // event after this method's sync section has run (Dart processes events
    // sequentially), so the guard below sees `true` and bails out. Setting
    // it after the draft save (the first await) left a window where two
    // submissions both passed this check and created the listing twice.
    if (isSubmitting.value) return;
    isSubmitting.value = true;
    error.value = null;

    final title = (values['title'] as String?)?.trim() ?? '';
    final description = (values['description'] as String?)?.trim() ?? '';
    final category = values['category'] as Category?;
    if (category == null) {
      error.value = 'Please select a category.';
      isSubmitting.value = false;
      return;
    }
    final condition = values['condition'] as Condition?;
    final barterOnly = this.barterOnly.value;
    final priceText = values['price'] as String?;
    final barterRequest = (values['barter_request'] as String?)?.trim();

    final photos = values['photos'] as List<ListingImage>?;
    final imagePaths = photos
        ?.whereType<LocalImage>()
        .map((img) => img.localPath)
        .toList();
    final parsedPrice = barterOnly
        ? null
        : NairaCurrencyInputFormatter.parse(priceText ?? '');

    // 1. Persist draft before touching the network.
    await _saveDraft(
      title: title,
      description: description,
      categoryId: category.id,
      condition: condition ?? Condition.isNew,
      price: parsedPrice?.amountMinor,
      barterRequest: barterRequest,
      barterOnly: barterOnly,
      imagePaths: imagePaths ?? const [],
    );

    final listingId = _createdListingId;

    Listing? listing;
    if (listingId != null) {
      // --- Retry path: the listing already exists, PATCH it ---
      final patch = UpdateListingRequest(
        title: title,
        description: description,
        condition: condition ?? Condition.isNew,
        categoryId: category.id,
        price: parsedPrice,
        barterRequest: barterOnly ? barterRequest : null,
      );

      final result = await _repository.update(listingId, patch);
      switch (result) {
        case Success(:final value):
          listing = value;
        case Failure(:final message):
          error.value = message;
          isSubmitting.value = false;
          return;
      }
    } else {
      // --- First attempt: create the listing ---
      final request = CreateListingRequest(
        title: title,
        description: description,
        condition: condition ?? Condition.isNew,
        categoryId: category.id,
        price: parsedPrice,
        barterRequest: barterOnly ? barterRequest : null,
      );

      final result = await _repository.create(request);
      switch (result) {
        case Success(:final value):
          listing = value;
        case Failure(:final message):
          error.value = message;
          isSubmitting.value = false;
          return;
      }
    }

    // Update the draft with the listing ID so a crash during upload
    // still has enough state to resume.
    _createdListingId = listing.id;
    await _saveDraft(
      title: title,
      description: description,
      categoryId: category.id,
      condition: condition ?? Condition.isNew,
      price: parsedPrice?.amountMinor,
      barterRequest: barterRequest,
      barterOnly: barterOnly,
      imagePaths: imagePaths ?? const [],
    );

    // 2. Upload photos.
    final uploadError = await _uploadPhotos(listing.id, photos);
    if (uploadError != null) {
      error.value = uploadError;
      isSubmitting.value = false;
      return;
    }

    // 3. All done — clear the draft and signal success.
    _createdListingId = null;
    await _draftRepository.clear();
    created.value = listing;

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

  // ---------------------------------------------------------------------------
  // Edit mode
  // ---------------------------------------------------------------------------

  /// Fetches an existing listing and populates the editor for editing.
  Future<void> loadListingForEdit(String id) async {
    isLoadingCategories.value = true;

    final result = await _repository.getListing(id);
    switch (result) {
      case Success(:final value):
        if (value == null) {
          error.value = 'Listing not found.';
          return;
        }
        existingListing.value = value;
        barterOnly.value = value.price == null && value.barterRequest != null;
      case Failure(:final message):
        error.value = message;
    }

    isLoadingCategories.value = false;
  }

  /// Submits an edit (PATCH) for an existing listing.
  Future<void> submitEdit(Map<String, dynamic> values) async {
    if (isSubmitting.value) return;
    if (!isEditMode) return;

    final listing = existingListing.value!;

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
    final parsedPrice = barterOnly
        ? null
        : NairaCurrencyInputFormatter.parse(priceText ?? '');

    isSubmitting.value = true;
    error.value = null;

    final patch = UpdateListingRequest(
      title: title,
      description: description,
      condition: condition ?? listing.condition,
      categoryId: category.id,
      price: parsedPrice,
      barterRequest: barterOnly ? barterRequest : null,
    );

    final result = await _repository.update(listing.id, patch);
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
    uploadProgress.dispose();
    existingListing.dispose();
    isUpdating.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
