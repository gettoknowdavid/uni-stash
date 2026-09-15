import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// Placeholder detail page for a single listing.
///
/// The [ListingSummary] is passed via `extra` from the home grid.
class ListingDetailPage extends StatelessWidget {
  const ListingDetailPage({required this.listing, super.key});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return UsPage(
      header: UsPageHeader(
        title: Text(listing.title),
        titleStyle: theme.textTheme.large,
      ),
      body: Center(
        child: Text(
          'Coming soon',
          style: theme.textTheme.muted.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}
