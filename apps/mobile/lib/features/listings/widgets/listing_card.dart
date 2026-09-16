import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({required this.listing, super.key});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: .all(color: theme.colorScheme.border),
        boxShadow: UsElevation.sm,
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(flex: 3, child: _ImageArea(listing: listing)),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const .all(UsSpacing.sm),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: theme.textTheme.p.copyWith(
                      fontSize: 14,
                      fontWeight: .w600,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(child: _PriceOrBarter(listing: listing)),
                      ConditionBadge(condition: listing.condition),
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

class _PriceOrBarter extends StatelessWidget {
  const _PriceOrBarter({required this.listing});
  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    if (listing.barterRequest != null) {
      return Text(
        'Barter',
        style: theme.textTheme.small.copyWith(
          fontWeight: .w700,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Text(
      listing.price?.display ?? '—',
      style: theme.textTheme.p.copyWith(
        fontSize: 14,
        fontWeight: .w700,
      ),
    );
  }
}

class _ImageArea extends StatelessWidget {
  const _ImageArea({required this.listing});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    Widget imageWidget = ColoredBox(
      color: theme.colorScheme.muted,
      child: Center(
        child: Icon(
          LucideIcons.image,
          size: 24,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );

    if (listing.images.isNotEmpty) {
      final imageUrl = listing.images[0].when(
        server: (_, url, _) => url,
        local: (_, _, _) => '',
      );

      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        fit: .contain,
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
      );
    }

    return Stack(
      fit: .expand,
      children: [
        imageWidget,
        Positioned(
          top: UsSpacing.xs,
          left: UsSpacing.xs,
          child: StatusBadge(status: listing.status),
        ),
      ],
    );
  }
}
