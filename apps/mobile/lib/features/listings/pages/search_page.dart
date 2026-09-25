import 'dart:async';

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/listings/data/saved_searches_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/search_view_model.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// SEARCH tab (main-shell branch 1): full-text search over listings with
/// category + price filters, recent searches and cursor pagination.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final ScrollController _scrollController;
  final _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    // Keep the field in sync with a query restored from a state change.
    _queryController.text = di<SearchViewModel>().query.value;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      unawaited(di<SearchViewModel>().loadMore());
    }
  }

  void _clearQuery() {
    _queryController.clear();
    di<SearchViewModel>().onQueryChanged('');
  }

  /// Applies a saved search term: mirror it into the field, then search.
  void _applyRecent(String term) {
    _queryController.text = term;
    di<SearchViewModel>().applyRecentSearch(term);
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('SEARCH')),
      gutters: .zero,
      body: Column(
        children: [
          _SearchField(
            controller: _queryController,
            onChanged: di<SearchViewModel>().onQueryChanged,
            onSubmitted: (_) => di<SearchViewModel>().submitSearch(),
            onClear: _clearQuery,
          ),
          const SizedBox(height: UsSpacing.lg),
          const _FilterBar(),
          const SizedBox(height: UsSpacing.lg),
          Expanded(
            child: _SearchBody(
              scrollController: _scrollController,
              onApplyRecent: _applyRecent,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        UsSpacing.lg,
        UsSpacing.sm,
        UsSpacing.lg,
        0,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return ShadInput(
            controller: controller,
            placeholder: const Text('Search textbooks, mini fridge...'),
            textInputAction: .search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            leading: Icon(
              LucideIcons.search,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            trailing: value.text.isEmpty
                ? null
                : ShadIconButton.ghost(
                    icon: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    onPressed: onClear,
                    width: 24,
                    height: 24,
                    padding: EdgeInsets.zero,
                    foregroundColor: theme.colorScheme.mutedForeground,
                  ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends SignalWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final model = di<SearchViewModel>();
    return Row(
      children: [
        Expanded(
          child: CategoryChips(
            categories: model.categories.value,
            selectedCategoryId: model.categoryId.value,
            onSelected: model.setCategory,
          ),
        ),
        const SizedBox(width: UsSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(right: UsSpacing.lg),
          child: _PriceFilterButton(model: model),
        ),
      ],
    );
  }
}

class _PriceFilterButton extends SignalWidget {
  const _PriceFilterButton({required this.model});

  final SearchViewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final active = model.hasPriceFilter;
    return ShadButton.outline(
      onPressed: () => _showPriceSheet(context, model),
      padding: const EdgeInsets.symmetric(horizontal: UsSpacing.md),
      decoration: ShadDecoration(
        border: ShadBorder.all(
          color: active ? theme.colorScheme.primary : theme.colorScheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(
            LucideIcons.slidersHorizontal,
            size: 14,
            color: active ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: UsSpacing.xs),
          Text(
            active ? _priceLabel(model) : 'PRICE',
            style: theme.textTheme.labelSm.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: active ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  String _priceLabel(SearchViewModel model) {
    final min = model.minPrice.value;
    final max = model.maxPrice.value;
    if (min != null && max != null) {
      return '${Money(amountMinor: min).display} – '
          '${Money(amountMinor: max).display}';
    }
    if (min != null) return 'FROM ${Money(amountMinor: min).display}';
    return 'UP TO ${Money(amountMinor: max!).display}';
  }

  Future<void> _showPriceSheet(BuildContext context, SearchViewModel model) {
    return showShadSheet<void>(
      context: context,
      side: .bottom,
      builder: (_) => _PriceFilterSheet(model: model),
    );
  }
}

/// Bottom sheet with min/max price inputs (Naira-masked, major units →
/// kobo). APPLY writes the range through the view model; CLEAR removes it.
class _PriceFilterSheet extends StatefulWidget {
  const _PriceFilterSheet({required this.model});

  final SearchViewModel model;

  @override
  State<_PriceFilterSheet> createState() => _PriceFilterSheetState();
}

class _PriceFilterSheetState extends State<_PriceFilterSheet> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: _format(widget.model.minPrice.value),
    );
    _maxController = TextEditingController(
      text: _format(widget.model.maxPrice.value),
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  String _format(int? minor) {
    if (minor == null) return '';
    return Money(amountMinor: minor).display;
  }

  void _apply() {
    final min = NairaCurrencyInputFormatter.parse(_minController.text)
        ?.amountMinor;
    final max = NairaCurrencyInputFormatter.parse(_maxController.text)
        ?.amountMinor;

    if (min != null && max != null && min > max) {
      setState(
        () => _validationError = 'Minimum price cannot exceed maximum.',
      );
      return;
    }

    widget.model.setPriceRange(min: min, max: max);
    context.pop();
  }

  void _clear() {
    widget.model.setPriceRange();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadSheet(
      title: const Text('FILTER BY PRICE'),
      description: const Text('Leave a field empty for no bound.'),
      actions: [
        ShadButton.outline(
          onPressed: _clear,
          child: const Text('CLEAR'),
        ),
        ShadButton(onPressed: _apply, child: const Text('APPLY')),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          ShadInput(
            controller: _minController,
            placeholder: const Text('Min price'),
            keyboardType: TextInputType.number,
            inputFormatters: [NairaCurrencyInputFormatter()],
          ),
          const SizedBox(height: UsSpacing.md),
          ShadInput(
            controller: _maxController,
            placeholder: const Text('Max price'),
            keyboardType: TextInputType.number,
            inputFormatters: [NairaCurrencyInputFormatter()],
          ),
          if (_validationError != null) ...[
            const SizedBox(height: UsSpacing.md),
            Text(
              _validationError!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchBody extends SignalWidget {
  const _SearchBody({
    required this.scrollController,
    required this.onApplyRecent,
  });

  final ScrollController scrollController;
  final ValueChanged<String> onApplyRecent;

  @override
  Widget build(BuildContext context) {
    final model = di<SearchViewModel>();

    // Idle: no query, no filters — offer recents + saved searches.
    if (!model.hasCriteria) {
      return _IdleState(model: model, onPick: onApplyRecent);
    }

    final results = model.results.value;
    final isLoading = model.isLoading.value;
    final error = model.error.value;

    if (results.isEmpty && isLoading) {
      return const Center(child: Spinner());
    }

    if (results.isEmpty && error != null) {
      return _ErrorView(message: error, onRetry: model.search);
    }

    if (results.isEmpty) {
      return const _NoResultsView();
    }

    return CustomMaterialIndicator(
      onRefresh: () async => model.refresh(),
      indicatorBuilder: (context, refreshing) => const Spinner(),
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(child: _SaveSearchBar(model: model)),
          _ResultsGrid(results: results),
          const _LoadMoreIndicator(),
        ],
      ),
    );
  }
}

/// A slim bar above the results offering to save the current criteria as
/// a named search (frontend-only persistence).
class _SaveSearchBar extends StatelessWidget {
  const _SaveSearchBar({required this.model});

  final SearchViewModel model;

  Future<void> _save(BuildContext context) async {
    final controller = TextEditingController(
      text: model.query.value.trim(),
    );
    final saved = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Save this search'),
        description: const Text(
          'Name it so you can re-run it later from the search page.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => dialogContext.pop(false),
            child: const Text('CANCEL'),
          ),
          ShadButton(
            onPressed: () => dialogContext.pop(true),
            child: const Text('SAVE'),
          ),
        ],
        child: ShadInput(
          controller: controller,
          placeholder: const Text('e.g. Mini fridge under 40k'),
          autofocus: true,
        ),
      ),
    );
    controller.dispose();
    if (saved != true) return;

    final ok = await model.saveCurrentSearch(controller.text);
    if (!context.mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(ok ? 'Search saved' : 'Could not save search'),
        description: Text(
          ok
              ? 'Find it under SAVED SEARCHES on this page.'
              : 'Please enter a name and try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        UsSpacing.lg,
        UsSpacing.md,
        UsSpacing.lg,
        0,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ShadButton.outline(
          onPressed: () => unawaited(_save(context)),
          child: Row(
            mainAxisSize: .min,
            children: [
              Icon(
                LucideIcons.bookmarkPlus,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: UsSpacing.xs),
              const Text('SAVE THIS SEARCH'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Idle state: recent searches + saved searches + a hint.
class _IdleState extends SignalWidget {
  const _IdleState({required this.model, required this.onPick});

  final SearchViewModel model;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final recent = model.recentSearches.value;
    final saved = model.savedSearches.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (saved.isNotEmpty) ...[
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Text('SAVED SEARCHES', style: theme.textTheme.labelSm),
                Icon(
                  LucideIcons.bellRing,
                  size: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
            ),
            const SizedBox(height: UsSpacing.md),
            for (final entry in saved)
              Padding(
                padding: const EdgeInsets.only(bottom: UsSpacing.sm),
                child: _SavedSearchTile(entry: entry),
              ),
            const SizedBox(height: UsSpacing.xxl),
          ],
          if (recent.isNotEmpty) ...[
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Text('RECENT SEARCHES', style: theme.textTheme.labelSm),
                GestureDetector(
                  onTap: model.clearRecentSearches,
                  child: Text(
                    'CLEAR',
                    style: theme.textTheme.labelSm.copyWith(
                      color: theme.colorScheme.mutedForeground,
                      decoration: .underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: UsSpacing.md),
            Wrap(
              spacing: UsSpacing.sm,
              runSpacing: UsSpacing.sm,
              children: [
                for (final term in recent)
                  GestureDetector(
                    onTap: () => onPick(term),
                    child: ShadCard(
                      padding: const .symmetric(
                        horizontal: UsSpacing.md,
                        vertical: UsSpacing.xs,
                      ),
                      rowCrossAxisAlignment: .center,
                      child: Row(
                        mainAxisSize: .min,
                        children: [
                          Icon(
                            LucideIcons.history,
                            size: 12,
                            color: theme.colorScheme.mutedForeground,
                          ),
                          const SizedBox(width: UsSpacing.xs),
                          Text(
                            term,
                            style: theme.textTheme.small.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: UsSpacing.xxl),
          ],
          Icon(
            LucideIcons.search,
            size: 48,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(height: UsSpacing.md),
          Text(
            'Search campus listings',
            textAlign: .center,
            style: theme.textTheme.p.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: UsSpacing.xxxl),
        ],
      ),
    );
  }
}

/// One saved search: tap to re-run, long-press to delete.
class _SavedSearchTile extends SignalWidget {
  const _SavedSearchTile({required this.entry});

  final SavedSearch entry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SearchViewModel>();
    return GestureDetector(
      behavior: .opaque,
      onTap: () => model.applySavedSearch(entry),
      onLongPress: () => model.removeSavedSearch(entry.id),
      child: ShadCard(
        padding: const .symmetric(
          horizontal: UsSpacing.md,
          vertical: UsSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.bookmark,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: UsSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.small.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      if (entry.query.isNotEmpty) '"${entry.query}"',
                      'saved search',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty results: offer saving the criteria for later.
class _NoResultsView extends SignalWidget {
  const _NoResultsView();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SearchViewModel>();
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Icon(
            LucideIcons.searchX,
            size: 48,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(height: UsSpacing.md),
          Text(
            'No results for "${model.query.value.trim()}"',
            textAlign: .center,
            style: theme.textTheme.p.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: UsSpacing.sm),
          ShadButton.outline(
            onPressed: model.clearFilters,
            child: const Text('CLEAR FILTERS'),
          ),
          const SizedBox(height: UsSpacing.xl),
          _SaveSearchBar(model: model),
        ],
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({required this.results});

  final List<ListingSummary> results;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(UsSpacing.lg),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final listing = results[index];
            return GestureDetector(
              onTap: () async {
                final result = await context.push<bool>(
                  UsRoutes.listingDetailsRoute(listing.id),
                  extra: listing,
                );
                // A `true` result means the listing changed (e.g. deleted)
                // — re-run the search so the grid isn't stale.
                if (result == true && context.mounted) {
                  unawaited(di<SearchViewModel>().refresh());
                }
              },
              child: ListingCard(listing: listing),
            );
          },
          childCount: results.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: UsSpacing.lg,
          crossAxisSpacing: UsSpacing.lg,
          childAspectRatio: 0.72,
        ),
      ),
    );
  }
}

class _LoadMoreIndicator extends SignalWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
    if (!di<SearchViewModel>().isLoadingMore.value) {
      return const SliverToBoxAdapter();
    }
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(UsSpacing.lg),
        child: Center(child: Spinner()),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UsSpacing.xl),
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: 48,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              message,
              textAlign: .center,
              style: theme.textTheme.p.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: UsSpacing.lg),
              ShadButton.outline(
                onPressed: onRetry,
                child: const Text('RETRY'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
