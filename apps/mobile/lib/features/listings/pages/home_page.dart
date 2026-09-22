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
          _SearchBar(controller: _searchController, onSubmitted: _handleSearch),
          const SizedBox(height: UsSpacing.lg),
          const _CategoryChips(),
          const SizedBox(height: UsSpacing.lg),
          Expanded(
            child: CustomMaterialIndicator(
              onRefresh: () async => di<ListingsViewModel>().refresh(),
              indicatorBuilder: (context, refreshing) => const Spinner(),
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
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

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
      height: 24,
      child: ListView.separated(
        scrollDirection: .horizontal,
        padding: const .symmetric(horizontal: UsSpacing.lg),
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
      child: ShadCard(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.card,
        border: selected
            ? .none
            : .all(color: theme.colorScheme.border, width: 1),
        padding: const .symmetric(horizontal: UsSpacing.lg),
        rowCrossAxisAlignment: .center,
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
        child: Center(child: Spinner()),
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
              onTap: () async {
                // A `true` result means the listing was deleted (or the
                // edit flow signalled a change) — refresh so the grid
                // doesn't keep showing stale data.
                final result = await context.push<bool>(
                  UsRoutes.listingDetailsRoute(listing.id),
                  extra: listing,
                );
                if (result == true && context.mounted) {
                  di<ListingsViewModel>().refresh();
                }
              },
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
        child: Center(child: Spinner()),
      ),
    );
  }
}
