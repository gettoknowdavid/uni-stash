import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
      body: CustomMaterialIndicator(
        onRefresh: () async => di<ListingsViewModel>().refresh(),
        indicatorBuilder: (context, refreshing) => const ShadSpinner(),
        child: const CustomScrollView(
          slivers: [
            _ListingsGrid(),
            _LoadMoreIndicator(),
          ],
        ),
      ),
    );
  }
}

/// The 2-column grid of listing cards.
class _ListingsGrid extends SignalHookWidget {
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

/// Shows a loading spinner at the bottom when paginating.
class _LoadMoreIndicator extends SignalHookWidget {
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
