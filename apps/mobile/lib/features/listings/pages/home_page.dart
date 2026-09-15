import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listings_view_model.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';
import 'package:uni_stash_mobile/theme/style.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('UNI·STASH')),
      floatingActionButton: ShadIconButton(
        icon: const Icon(LucideIcons.plus),
        decoration: const ShadDecoration(shadows: UsElevation.brutalist),
        onPressed: () => context.push(UsRoutes.listingEditor),
      ),
      body: RefreshIndicator(
        onRefresh: () async => di<ListingsViewModel>().refresh(),
        child: const CustomScrollView(
          slivers: [ListingsSliverGridWidget()],
        ),
      ),
    );
  }
}

class ListingsSliverGridWidget extends SignalHookWidget {
  const ListingsSliverGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = di<ListingsViewModel>();
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final listing = model.listings.value[index];

          const image = SizedBox(height: 155, child: Placeholder());
          // if (listing.images.isNotEmpty) {
          //   final imageUrl = listing.images[0].objectKey;
          //   image = CachedNetworkImage(imageUrl: imageUrl);
          // }

          return GestureDetector(
            onTap: () => context.push(
              UsRoutes.listingDetailsRoute(listing.id),
              extra: listing,
            ),
            child: ShadCard(
              padding: .zero,
              title: Text(listing.title),
              child: image,
            ),
          );
        },
        childCount: model.listings.value.length,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: getMaxExtent(context),
        mainAxisExtent: 286,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
    );
  }
}

// Explicitly calculates maximum allowed width per item to keep 2 columns
// on mobile
double getMaxExtent(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  const padding = 16.0 * 2; // Left + Right screen padding
  const spacing = 16.0; // Grid gap

  // Available space for items assuming 2 columns
  return (screenWidth - padding - spacing) / 2 + spacing;
}
