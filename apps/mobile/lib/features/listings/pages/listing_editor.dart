import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/listings/data/_data.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_draft.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class ListingEditor extends StatefulWidget {
  const ListingEditor({this.listingId, super.key});

  /// When provided, the editor operates in edit mode.
  final String? listingId;

  @override
  State<ListingEditor> createState() => _ListingEditorState();
}

class _ListingEditorState extends State<ListingEditor> {
  final _formKey = GlobalKey<ShadFormState>();

  late final ListingEditorViewModel _model;

  bool get _isEditMode => widget.listingId != null;

  @override
  void initState() {
    super.initState();
    // Page-scoped ViewModel (same pattern as the auth pages): a fresh
    // instance per visit, disposed by GetIt when the scope pops.
    di.pushNewScope(
      scopeName: 'listingEditorPage',
      init: (getIt) {
        getIt.registerLazySingleton<ListingEditorViewModel>(
          () => ListingEditorViewModel(
            di<ListingsRepository>(),
            di<CategoriesRepository>(),
            di<Logger>(),
          ),
        );
      },
    );
    _model = di<ListingEditorViewModel>();

    if (_isEditMode) {
      unawaited(_loadListingForEdit());
    } else {
      unawaited(_checkForDraft());
    }
  }

  Future<void> _loadListingForEdit() async {
    await _model.loadListingForEdit(widget.listingId!);
    if (!mounted) return;
    final listing = _model.existingListing.value;
    if (listing == null) return;
    _applyListingToForm(listing);
    _restoreDropdownFieldsFromListing(listing);
  }

  void _applyListingToForm(ListingDetailResponse listing) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final form = _formKey.currentState;
      if (form == null) return;

      // Pre-populate existing server images so the photo grid shows them
      // and validation passes without requiring the user to re-pick.
      form.fields['photos']?.didChange(listing.images);

      form.fields['title']?.didChange(listing.title);
      form.fields['description']?.didChange(listing.description);
      if (listing.price != null) {
        form.fields['price']?.didChange(listing.price!.display);
      }
      if (listing.barterRequest != null) {
        form.fields['barter_request']?.didChange(listing.barterRequest);
      }

      _model.barterOnly.value =
          listing.price == null && listing.barterRequest != null;

      _restoreDropdownFieldsFromListing(listing);
    });
  }

  void _restoreDropdownFieldsFromListing(ListingDetailResponse listing) {
    _model.categories.subscribe((categories) {
      if (categories.isEmpty) return;
      final match = categories.where((c) => c.id == listing.category.id);
      if (match.isNotEmpty) {
        _formKey.currentState?.fields['category']?.didChange(match.first);
      }
    });

    _formKey.currentState?.fields['condition']?.didChange(listing.condition);
  }

  Future<void> _checkForDraft() async {
    final draft = await _model.loadDraft();
    if (draft == null || !mounted) return;

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume draft?'),
        content: Text(
          draft.hasListingId
              ? 'You have an unfinished listing. '
                  'Would you like to resume where you left off?'
              : 'You have an unfinished listing draft. '
                  'Would you like to resume or start fresh?',
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('START FRESH'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('RESUME'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (resume == true) {
      _model.applyDraft(draft);
      _applyDraftToForm(draft);
    } else {
      await _model.discardDraft();
    }
  }

  void _applyDraftToForm(ListingDraft draft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final form = _formKey.currentState;
      if (form == null) return;

      // Restore scalar fields.
      form.fields['title']?.didChange(draft.title);
      form.fields['description']?.didChange(draft.description);
      if (draft.price != null) {
        form.fields['price']?.didChange(draft.price.toString());
      }
      if (draft.barterRequest != null) {
        form.fields['barter_request']?.didChange(draft.barterRequest);
      }

      // Restore the barter switch (drives which price branch is shown).
      _model.barterOnly.value = draft.barterOnly;

      // Restore category and condition once they've loaded.
      _restoreDropdownFields(draft);
    });
  }

  void _restoreDropdownFields(ListingDraft draft) {
    // Categories load async; poll until available, then set.
    _model.categories.subscribe((categories) {
      if (categories.isEmpty) return;
      final match = categories.where((c) => c.id == draft.categoryId);
      if (match.isNotEmpty) {
        _formKey.currentState?.fields['category']?.didChange(match.first);
      }
    });

    // Condition is synchronous (enum values available immediately).
    final condition = Condition.values.firstWhere(
      (c) => c.name == draft.condition,
      orElse: () => Condition.isNew,
    );
    _formKey.currentState?.fields['condition']?.didChange(condition);
  }

  @override
  void dispose() {
    // popScope() is async but dispose() is sync — calling it here would
    // discard the Future and never actually pop the scope.  Page-scoped
    // GetIt scopes are cleaned up in bulk by the logout flow via
    // popScopesTill(root).  For normal back-navigation the orphaned scope
    // is harmless (the next page pushes its own scope on top).
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SignalEffect(
      effect: (context) {
        final error = _model.error.value;
        if (error != null) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Publish Failed'),
              description: Text(error),
            ),
          );
          _model.consumeResult();
        }
        if (_model.created.value != null) {
          _model.consumeResult();
          context.pop(true);
        }
      },
      child: UsPage(
        header: UsPageHeader(
          title: Text(_isEditMode ? 'EDIT LISTING' : 'NEW LISTING'),
          titleStyle: theme.textTheme.large,
          foregroundColor: theme.colorScheme.foreground,
          automaticallyImplyLeading: false,
          actions: [
            ShadIconButton.ghost(
              iconSize: 20,
              height: 20,
              width: 20,
              icon: const Icon(LucideIcons.x),
              onPressed: () => context.pop(),
            ),
          ],
        ),
        gutters: .zero,
        body: ShadForm(
          key: _formKey,
          child: Column(
            children: [
              const Expanded(
                child: SingleChildScrollView(
                  padding: .all(16),
                  child: Column(
                    children: [
                      _PhotosField(),
                      SizedBox(height: 24),
                      _TitleField(),
                      SizedBox(height: 24),
                      _DescriptionField(),
                      SizedBox(height: 24),
                      _CategoryField(),
                      SizedBox(height: 24),
                      _ConditionField(),
                      SizedBox(height: 24),
                      _PriceSection(),
                    ],
                  ),
                ),
              ),
              ShadDecorator(
                decoration: ShadDecoration(
                  border: ShadBorder(
                    top: ShadBorderSide(
                      color: theme.colorScheme.border,
                    ),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: _SubmitButton(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotosField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final picker = ImagePicker();

    return ShadPhotosFormField(
      id: 'photos',
      label: const Text('PHOTOS'),
      onAddPhotos: (remainingSlots) async {
        // Photos stay local-only in the form; the ViewModel uploads them
        // (presign → PUT → confirm) after the listing is created, in submit.
        final picked = await picker.pickMultiImage(
          limit: remainingSlots,
          imageQuality: 80,
        );
        final stamp = DateTime.now().microsecondsSinceEpoch;
        return [
          for (var i = 0; i < picked.length; i++)
            ListingImage.local(
              id: 'local-$stamp-$i',
              position: i,
              localPath: picked[i].path,
            ),
        ];
      },
    );
  }
}

class _TitleField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    return ShadInputFormField(
      id: 'title',
      label: const Text('TITLE'),
      enabled: !model.isSubmitting.value,
      autocorrect: false,
      placeholder: const Text('Calculus textbook'),
      autovalidateMode: .onUserInteraction,
      validator: (value) {
        final v = value.trim();
        if (v.isEmpty) return 'Please enter a title.';
        if (v.length < 3) return 'Title must be at least 3 characters.';
        if (v.length > 100) return 'Title must be at most 100 characters.';
        return null;
      },
    );
  }
}

class _DescriptionField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    return ShadTextareaFormField(
      id: 'description',
      label: const Text('DESCRIPTION'),
      enabled: !model.isSubmitting.value,
      placeholder: const Text('Barely used. Bought for MTH201'),
      autovalidateMode: .onUserInteraction,
      validator: (value) {
        final v = value.trim();
        if (v.isEmpty) return 'Please enter a description.';
        if (v.length > 1000) {
          return 'Description must be at most 1000 characters.';
        }
        return null;
      },
    );
  }
}

class _CategoryField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();

    // Watch all three signals so the picker reacts to the fetch lifecycle.
    final categories = model.categories.value;
    final isLoading = model.isLoadingCategories.value;
    final error = model.categoriesError.value;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fetch failed and we have nothing to show: surface a retry
        // affordance instead of an empty, silently-disabled dropdown.
        if (error != null || categories.isEmpty) {
          return ShadSelectFormField<Category>(
            id: 'category',
            label: const Text('CATEGORY'),
            placeholder: const Text('No categories available'),
            minWidth: constraints.maxWidth,
            options: const [],
            trailing: GestureDetector(
              onTap: model.loadCategories,
              child: isLoading
                  ? const ShadSpinner(iconSize: 16, height: 16, width: 16)
                  : const Icon(LucideIcons.refreshCcw, size: 16),
            ),
            enabled: !isLoading,
            selectedOptionBuilder: (_, _) {
              return const Text('No categories available.');
            },
          );
        }

        return ShadSelectFormField<Category>(
          id: 'category',
          label: const Text('CATEGORY'),
          placeholder: const Text('Select a category'),
          minWidth: constraints.maxWidth,
          enabled: !model.isSubmitting.value && !isLoading,
          options: categories.map((value) {
            return ShadOption(value: value, child: Text(value.label));
          }).toList(),
          selectedOptionBuilder: (context, value) => Text(value.label),
          validator: (value) {
            if (value == null) return 'Please select a category.';
            return null;
          },
        );
      },
    );
  }
}

class _ConditionField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    return ShadButtonGroupFormField<Condition>(
      id: 'condition',
      label: const Text('CONDITION'),
      enabled: !model.isSubmitting.value,
      options: Condition.values,
      initialValue: Condition.isNew,
      itemBuilder:
          (
            context, {
            required value,
            required isSelected,
            required onPressed,
            required theme,
          }) {
            return ShadButton.outline(
              height: 32,
              onPressed: onPressed,
              foregroundColor: isSelected
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
              textStyle: theme.textTheme.small.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                letterSpacing: 0.5,
              ),
              padding: .zero,
              child: Text(value.message),
            );
          },
      validator: (value) {
        if (value == null) return 'You need to select a condition.';
        return null;
      },
    );
  }
}

/// Barter switch + the two mutually exclusive branches it controls.
///
/// The switch is not a `ShadForm` field: it lives on the view model as
/// `ListingEditorViewModel.barterOnly`, and `submit` maps exactly one of
/// price / barterRequest into the request.
class _PriceSection extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<ListingEditorViewModel>();
    final useBarter = model.barterOnly.value;
    final isBusy = model.isSubmitting.value;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text('BARTER ONLY, NO PRICE', style: theme.textTheme.labelMd),
            UsSwitch(
              value: useBarter,
              enabled: !isBusy,
              onChanged: (v) => model.barterOnly.value = v,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Field values survive unmount/remount (the form keeps unregistered
        // values by default), so the typed price comes back after toggling
        // barter off again.
        if (!useBarter) const _PriceField() else const _BarterRequestField(),
      ],
    );
  }
}

class _PriceField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    return ShadInputFormField(
      id: 'price',
      label: const Text('PRICE'),
      enabled: !model.isSubmitting.value,
      autocorrect: false,
      keyboardType: TextInputType.number,
      inputFormatters: [NairaCurrencyInputFormatter()],
      placeholder: const Text('₦0'),
      autovalidateMode: .onUserInteraction,
      validator: (value) {
        final amount = NairaCurrencyInputFormatter.parse(value);
        if (amount == null) return 'Please enter a price.';
        if (amount.amountMinor <= 0) return 'Price must be greater than ₦0.';
        return null;
      },
    );
  }
}

class _BarterRequestField extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    return ShadTextareaFormField(
      id: 'barter_request',
      label: const Text('WHAT DO YOU WANT IN EXCHANGE?'),
      enabled: !model.isSubmitting.value,
      placeholder: const Text(
        'e.g. A used iPhone 12 or anything worth ₦80,000',
      ),
      autovalidateMode: .onUserInteraction,
      validator: (value) {
        final v = value.trim();
        if (v.isEmpty) {
          return 'Please describe what you want in exchange.';
        }
        if (v.length > 1000) {
          return 'Exchange description must be at most 1000 characters.';
        }
        return null;
      },
    );
  }
}

class _SubmitButton extends SignalHookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final model = di<ListingEditorViewModel>();
    final isBusy = model.isSubmitting.value;
    final uploadProgress = model.uploadProgress.value;
    final isEdit = model.isEditMode;

    return SizedBox(
      width: double.infinity,
      child: ShadButton(
        onPressed: isBusy ? null : () => _handleSubmit(context),
        child: isBusy
            ? Row(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  const ShadSpinner(iconSize: 16),
                  if (uploadProgress != null) ...[
                    const SizedBox(width: 8),
                    Text(uploadProgress),
                  ],
                ],
              )
            : Text(isEdit ? 'UPDATE LISTING' : 'PUBLISH LISTING'),
      ),
    );
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final form = ShadForm.of(context);
    if (!form.saveAndValidate()) return;
    final model = di<ListingEditorViewModel>();
    if (model.isEditMode) {
      await model.submitEdit(form.value);
    } else {
      await model.submit(form.value);
    }
  }
}
