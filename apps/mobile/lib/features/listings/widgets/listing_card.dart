import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// A neo-brutalist listing card for the browse grid.
///
/// Displays the first image, title, price (or barter label), condition badge,
/// and a status overlay. Hard corners throughout — no border radius.
class ListingCard extends StatelessWidget {
  const ListingCard({required this.listing, super.key});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(color: theme.colorScheme.border),
        boxShadow: UsElevation.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          // --- Image area with status badge ---
          Expanded(
            flex: 3,
            child: _ImageArea(listing: listing),
          ),

          // --- Text content ---
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(UsSpacing.sm),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  // Title
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.p.copyWith(
                      fontSize: 14,
                      fontWeight: .w600,
                    ),
                  ),

                  const Spacer(),

                  // Price / barter + condition
                  Row(
                    children: [
                      Expanded(
                        child: listing.barterRequest != null
                            ? Text(
                                'Barter',
                                style: theme.textTheme.small.copyWith(
                                  fontWeight: .w700,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : Text(
                                listing.price?.display ?? '—',
                                style: theme.textTheme.p.copyWith(
                                  fontSize: 14,
                                  fontWeight: .w700,
                                ),
                              ),
                      ),
                      _ConditionBadge(condition: listing.condition),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the first listing image with a status badge overlay.
class _ImageArea extends StatelessWidget {
  const _ImageArea({required this.listing});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final hasImage = listing.images.isNotEmpty;
    final imageUrl = hasImage
        ? listing.images[0].when(
            server: (_, url, _) => url,
            local: (_, _, _) => '',
          )
        : '';
    final imageWidget = hasImage && imageUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: imageUrl,
            fit: .cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, _) => Center(
              child: Icon(
                LucideIcons.image,
                size: 24,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            errorWidget: (_, _, _) => Center(
              child: Icon(
                LucideIcons.imageOff,
                size: 24,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          )
        : ColoredBox(
            color: theme.colorScheme.muted,
            child: Center(
              child: Icon(
                LucideIcons.image,
                size: 24,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          );

    return Stack(
      fit: .expand,
      children: [
        imageWidget,
        // Status badge
        Positioned(
          top: UsSpacing.xs,
          left: UsSpacing.xs,
          child: _StatusBadge(status: listing.status),
        ),
      ],
    );
  }
}

/// Hard-cornered status badge (ACTIVE / RESERVED / SOLD).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final (label, bgColor, fgColor) = switch (status) {
      ListingStatus.active => (
        'ACTIVE',
        theme.colorScheme.primary,
        theme.colorScheme.primaryForeground,
      ),
      ListingStatus.reserved => (
        'RESERVED',
        theme.colorScheme.foreground,
        theme.colorScheme.background,
      ),
      ListingStatus.sold => (
        'SOLD',
        theme.colorScheme.muted,
        theme.colorScheme.mutedForeground,
      ),
      ListingStatus.deleted => (
        'DELETED',
        theme.colorScheme.destructive,
        theme.colorScheme.destructiveForeground,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UsSpacing.sm,
          vertical: UsSpacing.xxs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSm.copyWith(
            color: fgColor,
            fontWeight: .w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Hard-cornered condition badge (NEW / USED / FAIR).
class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.condition});

  final Condition condition;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UsSpacing.sm,
          vertical: UsSpacing.xxs,
        ),
        child: Text(
          condition.message,
          style: theme.textTheme.labelSm.copyWith(
            fontWeight: .w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
