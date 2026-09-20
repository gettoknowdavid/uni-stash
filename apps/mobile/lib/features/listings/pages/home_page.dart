import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/categories_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listings_view_model.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ScrollController _scrollController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    // Sync search controller with existing query
    final model = di<ListingsViewModel>();
    _searchController.text = model.query.value;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      di<ListingsViewModel>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('UNI·STASH')),
      gutters: .zero,
      floatingActionButton: ShadIconButton(
        icon: const Icon(LucideIcons.plus),
        decoration: const ShadDecoration(shadows: UsElevation.brutalist),
        onPressed: () async {
          final result = await context.push(UsRoutes.listingEditor);
          if (result == true && context.mounted) {
            di<ListingsViewModel>().refresh();
          }
        },
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            onSubmitted: _handleSearch,
            onFilterTap: _showFilterSheet,
          ),
          const _CategoryChips(),
          Expanded(
            child: CustomMaterialIndicator(
              onRefresh: () async => di<ListingsViewModel>().refresh(),
              indicatorBuilder: (context, refreshing) => const ShadSpinner(),
              child: const CustomScrollView(
                slivers: [
                  _ListingsGrid(),
                  _LoadMoreIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSearch(String value) {
    final model = di<ListingsViewModel>();
    model.query.value = value;
    model.fetch();
  }

  Future<void> _showFilterSheet() {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => const _FilterBottomSheet(),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.onFilterTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onFilterTap;

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
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: controller,
              placeholder: const Text('Search textbooks, mini fridge...'),
              onSubmitted: onSubmitted,
              trailing: Icon(
                LucideIcons.search,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: UsSpacing.sm),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: .all(color: theme.colorScheme.borderStrong),
              ),
              child: Icon(
                LucideIcons.listFilter,
                size: 20,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends SignalStatefulWidget {
  const _CategoryChips();

  @override
  State<_CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<_CategoryChips> {
  List<Category>? _categories;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    final repo = di<CategoriesRepository>();
    final result = await repo.list();
    if (result case Success(value: final response) when mounted) {
      setState(() => _categories = response.categories);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = di<ListingsViewModel>();
    final selectedCategoryId = model.categoryId.value;

    final chips = <Widget>[
      _CategoryChip(
        label: 'ALL',
        selected: selectedCategoryId == null,
        onTap: () {
          model.categoryId.value = null;
          model.fetch();
        },
      ),
      if (_categories != null)
        for (final cat in _categories!)
          _CategoryChip(
            label: cat.label.toUpperCase(),
            selected: selectedCategoryId == cat.id,
            onTap: () {
              model.categoryId.value = cat.id;
              model.fetch();
            },
          ),
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: UsSpacing.lg,
          vertical: UsSpacing.sm,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: UsSpacing.sm),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.card,
          border: .all(color: theme.colorScheme.borderStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: UsSpacing.md,
            vertical: UsSpacing.xs,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSm.copyWith(
              color: selected
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  const _FilterBottomSheet();

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  int? _selectedCategoryId;
  List<Category>? _categories;

  @override
  void initState() {
    super.initState();
    final model = di<ListingsViewModel>();
    _selectedCategoryId = model.categoryId.value;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    final repo = di<CategoriesRepository>();
    final result = await repo.list();
    if (result case Success(value: final response) when mounted) {
      setState(() => _categories = response.categories);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(color: theme.colorScheme.borderStrong, width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UsSpacing.lg,
              UsSpacing.lg,
              UsSpacing.lg,
              UsSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SELECT CATEGORY',
                  style: theme.textTheme.h3.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    LucideIcons.x,
                    size: 24,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ],
            ),
          ),

          // Category list
          if (_categories == null)
            const Padding(
              padding: EdgeInsets.all(UsSpacing.lg),
              child: Center(child: ShadSpinner()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // ALL CATEGORIES option
                  _FilterOption(
                    label: 'ALL CATEGORIES',
                    selected: _selectedCategoryId == null,
                    onTap: () => setState(() => _selectedCategoryId = null),
                  ),
                  for (final cat in _categories!)
                    _FilterOption(
                      label: cat.label.toUpperCase(),
                      selected: _selectedCategoryId == cat.id,
                      onTap: () => setState(() => _selectedCategoryId = cat.id),
                    ),
                ],
              ),
            ),

          // Apply button
          Padding(
            padding: const EdgeInsets.all(UsSpacing.lg),
            child: ShadButton(
              onPressed: _applyFilter,
              child: const Text('APPLY FILTERS'),
            ),
          ),
        ],
      ),
    );
  }

  void _applyFilter() {
    final model = di<ListingsViewModel>();
    model.categoryId.value = _selectedCategoryId;
    model.fetch();
    Navigator.pop(context);
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UsSpacing.lg,
          vertical: UsSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.card,
                border: .all(color: theme.colorScheme.borderStrong),
              ),
              child: selected
                  ? Icon(
                      LucideIcons.check,
                      size: 16,
                      color: theme.colorScheme.primaryForeground,
                    )
                  : null,
            ),
            const SizedBox(width: UsSpacing.md),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingsGrid extends SignalWidget {
  const _ListingsGrid();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final model = di<ListingsViewModel>();
    final listings = model.listings.value;
    final isLoading = model.isLoading.value;

    // Initial loading skeleton
    if (listings.isEmpty && isLoading) {
      return const SliverFillRemaining(
        child: Center(child: ShadSpinner()),
      );
    }

    // Empty state
    if (listings.isEmpty && !isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.packageOpen,
                size: 48,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(height: UsSpacing.md),
              Text(
                'No listings yet',
                style: theme.textTheme.p.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(UsSpacing.lg),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final listing = listings[index];
            return GestureDetector(
              onTap: () => context.push(
                UsRoutes.listingDetailsRoute(listing.id),
                extra: listing,
              ),
              child: ListingCard(listing: listing),
            );
          },
          childCount: listings.length,
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
    final model = di<ListingsViewModel>();
    final isLoadingMore = model.isLoadingMore.value;

    if (!isLoadingMore) return const SliverToBoxAdapter();

    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(UsSpacing.lg),
        child: Center(child: ShadSpinner()),
      ),
    );
  }
}
