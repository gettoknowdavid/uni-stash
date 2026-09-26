import 'dart:async';

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/blocks/pages/block_user_dialog.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/features/profile/data/users_repository.dart';
import 'package:uni_stash_mobile/features/profile/models/public_profile.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Page-scoped view model backing [UserProfilePage].
class UserProfileViewModel implements Disposable {
  UserProfileViewModel(this._repository, this.userId);

  final UsersRepository _repository;
  final String userId;

  final FlutterSignal<PublicProfile?> profile =
      signal<PublicProfile?>(null);
  final FlutterSignal<List<ListingSummary>> listings =
      signal<List<ListingSummary>>(const []);
  final FlutterSignal<bool> isLoading = signal(true);
  final FlutterSignal<bool> isLoadingMore = signal(false);
  final FlutterSignal<String?> error = signal<String?>(null);
  final FlutterSignal<bool> hasMore = signal(false);
  String? _cursor;
  bool _disposed = false;

  Future<void> fetch() async {
    isLoading.value = true;
    error.value = null;
    _cursor = null;
    hasMore.value = false;

    final profileResult = await _repository.getProfile(userId);
    final listingsResult = await _repository.getUserListings(userId);
    if (_disposed) return;

    switch (profileResult) {
      case Success(:final value):
        profile.value = value;
      case Failure(:final message):
        error.value = message;
    }

    switch (listingsResult) {
      case Success(:final value):
        listings.value = value.listings;
        _cursor = value.nextCursor;
        hasMore.value = value.nextCursor != null;
      case Failure():
        // Profile still renders; listings section shows empty.
    }

    isLoading.value = false;
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || _cursor == null) return;
    isLoadingMore.value = true;
    final result = await _repository.getUserListings(userId, cursor: _cursor);
    if (_disposed) return;
    switch (result) {
      case Success(:final value):
        listings.value = [...listings.value, ...value.listings];
        _cursor = value.nextCursor;
        hasMore.value = value.nextCursor != null;
      case Failure():
    }
    isLoadingMore.value = false;
  }

  @override
  Future<void> onDispose() async {
    _disposed = true;
  }
}

/// Another user's public profile: identity, rating, stats, listing grid,
/// and a block action.
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({required this.userId, super.key});

  final String userId;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'userProfilePage',
      init: (getIt) {
        getIt.registerLazySingleton<UserProfileViewModel>(
          () => UserProfileViewModel(di<UsersRepository>(), widget.userId),
        );
      },
    );
    unawaited(di<UserProfileViewModel>().fetch());
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
      header: UsPageHeader(title: Text('PROFILE')),
      body: _Body(),
    );
  }
}

class _Body extends SignalHookWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<UserProfileViewModel>();

    if (model.isLoading.value) return const Center(child: Spinner());

    final profile = model.profile.value;
    final error = model.error.value;
    if (error != null && profile == null) {
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
    if (profile == null) return const Center(child: Spinner());

    return CustomMaterialIndicator(
      onRefresh: model.fetch,
      indicatorBuilder: (context, _) => const Spinner(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) unawaited(model.loadMore());
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _ProfileHeader(profile: profile)),
            SliverToBoxAdapter(
              child: _ListingGrid(model: model),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const .all(16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              UsAvatar(
                name: profile.displayName,
                photoUrl: profile.photoUrl,
                size: 56,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      profile.displayName,
                      style: theme.textTheme.h3.copyWith(fontWeight: .bold),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                    Text(
                      '@${profile.domain} · '
                      'joined ${timeago.format(profile.joinedAt)}',
                      style: theme.textTheme.muted,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                ),
              ),
              ShadIconButton.ghost(
                icon: Icon(
                  LucideIcons.userX,
                  color: theme.colorScheme.destructive,
                ),
                onPressed: () => unawaited(
                  showBlockUserDialog(
                    context,
                    userId: profile.id,
                    userName: profile.displayName,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: profile.averageRating?.toStringAsFixed(1) ?? '—',
                  label: 'RATING',
                  subtitle: '${profile.reviewCount} review'
                      '${profile.reviewCount == 1 ? '' : 's'}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: '${profile.activeListings}',
                  label: 'ACTIVE LISTINGS',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: .centerLeft,
            child: Text('LISTINGS', style: theme.textTheme.labelSm),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.subtitle});

  final String value;
  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        children: [
          Text(value, style: theme.textTheme.h2),
          Text(label, style: theme.textTheme.labelSm),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }
}

/// Public listings grid — reuses the search page's results grid.
class _ListingGrid extends SignalHookWidget {
  const _ListingGrid({required this.model});

  final UserProfileViewModel model;

  @override
  Widget build(BuildContext context) {
    final listings = model.listings.value;

    if (listings.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: .all(24),
          child: Center(
            child: Text('No active listings'),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const .only(bottom: 32),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final listing = listings[index];
            return GestureDetector(
              onTap: () => unawaited(
                context.push<bool>(
                  UsRoutes.listingDetailsRoute(listing.id),
                  extra: listing,
                ),
              ),
              child: ListingCard(listing: listing),
            );
          },
          childCount: listings.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
      ),
    );
  }
}
