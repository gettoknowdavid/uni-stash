import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
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
      body: CustomScrollView(
        slivers: [ListingsSliverGridWidget()],
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
          return GestureDetector(
            onTap: () => context.push(
              UsRoutes.listingDetailsRoute(listing.id),
              extra: listing,
            ),
            child: ShadCard(title: Text(listing.title),),
          );
        },
        childCount: model.listings.value.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
    );
  }
}
