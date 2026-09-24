import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/listings/data/_data.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/features/profile/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// MY LISTINGS (profile menu): every listing the signed-in user owns,
/// cursor-paginated. Tapping a card opens the listing detail; returning
/// after a change (delete, mark sold) refreshes the grid.
class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'myListings',
      init: (getIt) {
        getIt.registerLazySingleton<MyListingsViewModel>(
          () => MyListingsViewModel(
            di<ListingsRepository>(),
            sellerId: di<UserViewModel>().currentUser.value?.id ?? '',
          ),
          dispose: (model) => model.dispose(),
        );
      },
    );
    di<MyListingsViewModel>().fetch();
  }

  @override
  void dispose() {
    // popScope() is async but dispose() is sync, so the pop is fired,
    // not awaited — see [popPageScope].
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      gutters: .zero,
      header: UsPageHeader(title: Text('MY LISTINGS')),
      body: _MyListingsBody(),
    );
  }
}

class _MyListingsBody extends SignalWidget {
  const _MyListingsBody();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<MyListingsViewModel>();
    final listings = model.listings.value;
    final isLoading = model.isLoading.value;
    final isLoadingMore = model.isLoadingMore.value;
    final error = model.error.value;

    if (isLoading && listings.isEmpty) {
      return const Center(child: Spinner());
    }

    if (error != null && listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(error, style: theme.textTheme.muted, textAlign: .center),
            const SizedBox(height: 16),
            ShadButton.outline(
              onPressed: model.fetch,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            const Icon(
              LucideIcons.tag,
              size: 48,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              'You have no listings yet',
              style: theme.textTheme.muted,
            ),
          ],
        ),
      );
    }

    // Near the end of the scroll extent → fetch the next cursor page.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) {
          model.loadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const .all(UsSpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: UsSpacing.lg,
          crossAxisSpacing: UsSpacing.lg,
          childAspectRatio: 0.72,
        ),
        itemCount: listings.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == listings.length) {
            return const Center(child: Spinner());
          }
          final listing = listings[index];
          return GestureDetector(
            onTap: () async {
              final changed = await context.push<bool>(
                UsRoutes.listingDetailsRoute(listing.id),
                extra: listing,
              );
              // A `true` result means the listing changed (e.g. deleted)
              // — re-fetch so the grid isn't stale.
              if (changed == true && context.mounted) {
                unawaited(Future<void>.sync(model.refresh));
              }
            },
            child: ListingCard(listing: listing),
          );
        },
      ),
    );
  }
}

/// SAVED ITEMS (profile menu): the user's bookmarked listings, stored
/// locally via [SavedItemsRepository] (no saved-items backend yet).
///
/// The view model resolves each bookmarked id against the listings API;
/// listings that no longer resolve (sold-and-hidden, deleted by their
/// owner) drop off the list automatically.
class SavedItemsPage extends StatefulWidget {
  const SavedItemsPage({super.key});

  @override
  State<SavedItemsPage> createState() => _SavedItemsPageState();
}

class _SavedItemsPageState extends State<SavedItemsPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'savedItems',
      init: (getIt) {
        getIt.registerLazySingleton<SavedItemsViewModel>(
          () => SavedItemsViewModel(
            di<ListingsRepository>(),
            di<SavedItemsRepository>(),
          ),
          dispose: (model) => model.dispose(),
        );
      },
    );
    di<SavedItemsViewModel>().fetch();
  }

  @override
  void dispose() {
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      gutters: .zero,
      header: UsPageHeader(title: Text('SAVED ITEMS')),
      body: _SavedItemsBody(),
    );
  }
}

class _SavedItemsBody extends SignalWidget {
  const _SavedItemsBody();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SavedItemsViewModel>();
    final listings = model.listings.value;
    final isLoading = model.isLoading.value;
    final error = model.error.value;

    if (isLoading && listings.isEmpty) {
      return const Center(child: Spinner());
    }

    if (error != null && listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(error, style: theme.textTheme.muted, textAlign: .center),
            const SizedBox(height: 16),
            ShadButton.outline(
              onPressed: model.fetch,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              LucideIcons.bookmark,
              size: 48,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              'Nothing saved yet',
              style: theme.textTheme.muted,
            ),
            const SizedBox(height: UsSpacing.sm),
            Text(
              'Tap the bookmark on a listing to save it here.',
              textAlign: .center,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const .all(UsSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: UsSpacing.lg,
        crossAxisSpacing: UsSpacing.lg,
        childAspectRatio: 0.72,
      ),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        final listing = listings[index];
        return GestureDetector(
          onTap: () =>
              context.push(UsRoutes.listingDetailsRoute(listing.id)),
          child: ListingCard(listing: listing),
        );
      },
    );
  }
}
