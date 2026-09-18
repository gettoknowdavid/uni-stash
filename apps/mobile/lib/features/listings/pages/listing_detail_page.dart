import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/listings/data/_data.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Placeholder detail page for a single listing.
///
/// The [ListingSummary] is passed via `extra` from the home grid.
class ListingDetailPage extends StatefulWidget {
  const ListingDetailPage({required this.id, super.key});

  final String id;

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  @override
  void initState() {
    super.initState();
    di.pushNewScope(
      scopeName: 'listing-${widget.id}',
      init: (getIt) {
        getIt.registerLazySingletonAsync<ListingDetailViewModel>(
          () async => ListingDetailViewModel(di<ListingsRepository>()),
          onCreated: (model) async => model.fetch(widget.id),
          dispose: (vm) => vm.dispose(),
        );
      },
    );
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
    return UsPage(
      gutters: .zero,
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: di.isReady<ListingDetailViewModel>(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != .done) {
                return const UsPage(body: Center(child: ShadSpinner()));
              }

              if (snapshot.hasError) {
                return UsPage(
                  body: _ErrorView(message: snapshot.error.toString()),
                );
              }

              return _ListingDetailView(id: widget.id);
            },
          ),
          const Positioned(left: 16, top: 16, child: UsBackButton()),
        ],
      ),
    );
  }
}

class _ListingDetailView extends StatelessWidget {
  const _ListingDetailView({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SignalBuilder(
      builder: (context) {
        final listingModel = di<ListingDetailViewModel>();
        final detail = listingModel.detail.value;
        final isLoading = listingModel.isLoading.value;
        final error = listingModel.error.value;

        if (detail == null && isLoading && error == null) {
          return const UsPage(
            body: Center(child: ShadSpinner()),
          );
        }

        if (detail == null && error != null) {
          return UsPage(
            body: Center(
              child: _ErrorView(
                message: error,
                onRetry: () => listingModel.fetch(id),
              ),
            ),
          );
        }

        if (detail == null) {
          return const UsPage(
            body: Center(child: Text('Listing not found')),
          );
        }

        final currentUserId = di<UserViewModel>().currentUser.value?.id;
        final isMe = currentUserId == detail.seller.id;

        final date = timeago.format(detail.createdAt);

        return UsPage(
          gutters: .zero,
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const .only(bottom: 48),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    _ImageCarousel(images: detail.images),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const .symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: .start,
                        mainAxisAlignment: .spaceBetween,
                        children: [
                          // StatusBadge(status: detail.status),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: [
                                Text(
                                  detail.title,
                                  style: theme.textTheme.h1,
                                  overflow: .ellipsis,
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 4),
                                RichText(
                                  text: TextSpan(
                                    style: theme.textTheme.small,
                                    children: [
                                      TextSpan(text: 'Listed $date'),
                                      const TextSpan(text: ' • '),
                                      TextSpan(text: detail.category.label),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            detail.price?.display ?? '—',
                            style: theme.textTheme.labelLg.copyWith(
                              fontSize: 18,
                              fontWeight: .w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const .symmetric(horizontal: 16),
                      child: Text(
                        'DESCRIPTION',
                        style: theme.textTheme.labelSm,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const .symmetric(horizontal: 16),
                      child: Text(
                        detail.description,
                        style: theme.textTheme.p,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            'CATEGORY',
                            style: theme.textTheme.labelSm,
                          ),
                        ),
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            detail.category.label,
                            style: theme.textTheme.p,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ShadSeparator.horizontal(
                      margin: const .symmetric(horizontal: 16),
                      color: theme.colorScheme.borderStrong,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            'CONDITION',
                            style: theme.textTheme.labelSm,
                          ),
                        ),
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            detail.condition.name,
                            style: theme.textTheme.p,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ShadSeparator.horizontal(
                      margin: const .symmetric(horizontal: 16),
                      color: theme.colorScheme.borderStrong,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            'STATUS',
                            style: theme.textTheme.labelSm,
                          ),
                        ),
                        Padding(
                          padding: const .symmetric(horizontal: 16),
                          child: Text(
                            detail.status.name,
                            style: theme.textTheme.p,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!isMe) ...[
                      ShadSeparator.horizontal(
                        margin: const .symmetric(horizontal: 16),
                        color: theme.colorScheme.borderStrong,
                      ),
                      const SizedBox(height: 24),
                      _SellerDetails(detail: detail),
                    ],
                  ],
                ),
              ),
              Positioned(
                right: 16,
                top: 16,
                child: Column(
                  spacing: 16,
                  children: [
                    if (!isMe)
                      _BookmarkButton(sellerId: detail.seller.id, size: 30),
                    if (isMe)
                      _EditButton(id: id, sellerId: detail.seller.id, size: 30),
                  ],
                ),
              ),
            ],
          ),
          footer: isMe ? null : const _MessageSellerButton(),
        );
      },
    );
  }
}

class _SellerDetails extends StatelessWidget {
  const new({required this.detail});

  final ListingDetailResponse detail;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 16),
      child: Row(
        spacing: 12,
        children: [
          UsAvatar(
            name: detail.seller.displayName,
            photoUrl: detail.seller.photoUrl,
            size: 40,
            verified: detail.seller.emailVerified,
            verifiedLabel: '✓',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  detail.seller.displayName,
                  style: theme.textTheme.h2.copyWith(
                    fontWeight: .bold,
                  ),
                  overflow: .ellipsis,
                  maxLines: 1,
                ),
                Text(
                  detail.seller.emailVerified
                      ? 'Verified student'
                      : 'Student • @${detail.seller.domain}',
                  style: theme.textTheme.muted,
                  overflow: .ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageSellerButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDecorator(
      decoration: ShadDecoration(
        border: ShadBorder(
          top: ShadBorderSide(
            color: theme.colorScheme.border,
          ),
        ),
      ),
      child: const Padding(
        padding: .all(16),
        child: ShadButton(
          width: double.infinity,
          child: Text('MESSAGE SELLER'),
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.id, required this.sellerId, this.size = 40});
  final String id;
  final String sellerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: ShadIconButton(
        backgroundColor: theme.colorScheme.accent,
        foregroundColor: theme.colorScheme.foreground,
        hoverBackgroundColor: theme.colorScheme.muted,
        pressedBackgroundColor: theme.colorScheme.foreground,
        pressedForegroundColor: theme.colorScheme.accent,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: theme.colorScheme.foreground,
            width: 2,
            radius: .zero,
          ),
        ),
        onPressed: () async {
          await context.push<void>(UsRoutes.listingEditRoute(id));
        },
        icon: Icon(LucideIcons.pencil, size: size * 0.6),
      ),
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({required this.sellerId, this.size = 40});
  final String sellerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: ShadIconButton(
        backgroundColor: theme.colorScheme.accent,
        foregroundColor: theme.colorScheme.foreground,
        hoverBackgroundColor: theme.colorScheme.muted,
        pressedBackgroundColor: theme.colorScheme.foreground,
        pressedForegroundColor: theme.colorScheme.accent,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: theme.colorScheme.foreground,
            width: 2,
            radius: .zero,
          ),
        ),
        onPressed: () {},
        icon: Icon(LucideIcons.bookmark, size: size * 0.6),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  const _ImageCarousel({required this.images});

  final List<ListingImage> images;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String? _imageUrl(ListingImage image) {
    return image.when(
      server: (_, url, _) => url,
      local: (_, _, _) => null,
    );
  }

  bool _hasUrl(ListingImage image) => _imageUrl(image) != null;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final images = widget.images;

    // Filter to server images only
    final serverImages = images.where(_hasUrl).toList();

    if (serverImages.isEmpty) {
      return SizedBox(
        height: 360,
        width: double.infinity,
        child: ShadDecorator(
          decoration: ShadDecoration(
            color: theme.colorScheme.muted,
            border: ShadBorder(
              bottom: ShadBorderSide(
                color: theme.colorScheme.borderStrong,
              ),
            ),
          ),
          child: Icon(
            LucideIcons.image,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: .min,
      children: [
        // Main carousel
        SizedBox(
          height: 360,
          width: double.infinity,
          child: ShadDecorator(
            decoration: ShadDecoration(
              color: theme.colorScheme.muted,
              border: ShadBorder(
                bottom: ShadBorderSide(
                  color: theme.colorScheme.borderStrong,
                ),
              ),
            ),
            child: PageView.builder(
              controller: _pageController,
              itemCount: serverImages.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final url = _imageUrl(serverImages[index])!;
                return CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(
                    child: ShadSpinner(),
                  ),
                  errorWidget: (_, _, _) => Center(
                    child: Icon(
                      LucideIcons.imageOff,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Thumbnail strip
        if (serverImages.length > 1)
          Container(
            height: 48,
            color: theme.colorScheme.background,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const .symmetric(horizontal: 16, vertical: 8),
              itemCount: serverImages.length,
              itemBuilder: (context, index) {
                final isSelected = index == _currentPage;
                return GestureDetector(
                  onTap: () => _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const .only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.muted,
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: _imageUrl(serverImages[index])!,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
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
    return Padding(
      padding: const .all(24),
      child: Column(
        mainAxisSize: .min,
        children: [
          Text(
            message,
            textAlign: .center,
            style: theme.textTheme.muted.copyWith(
              color: theme.colorScheme.destructive,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            ShadButton.outline(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
