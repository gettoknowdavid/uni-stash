import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/sell_dashboard_view_model.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/features/sales/models/models.dart';
import 'package:uni_stash_mobile/router/_router.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// SELL tab: the seller's dashboard — headline stats, listings awaiting
/// handover, recent activity and the entry point to the listing editor.
/// The editor itself lives at `/listings/editor` (pushed on top); this
/// page is the storefront home base.
class SellPage extends StatefulWidget {
  const SellPage({super.key});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh stats every time the tab becomes visible (returning from a
    // handover, a new listing, etc.). The VM no-ops past the first load's
    // bookkeeping itself.
    di<SellDashboardViewModel>().onTabShown();
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('SELL')),
      gutters: .zero,
      floatingActionButton: ShadIconButton(
        icon: const Icon(LucideIcons.plus),
        decoration: const ShadDecoration(shadows: UsElevation.brutalist),
        onPressed: () => context.push(UsRoutes.listingEditor),
      ),
      body: CustomMaterialIndicator(
        onRefresh: () async => di<SellDashboardViewModel>().refresh(),
        indicatorBuilder: (context, refreshing) => const Spinner(),
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: UsSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: UsSpacing.lg),
              _NewListingButton(),
              SizedBox(height: UsSpacing.xl),
              _StatsStrip(),
              SizedBox(height: UsSpacing.xl),
              _ReservedSection(),
              SizedBox(height: UsSpacing.xl),
              _MyListingsSection(),
              SizedBox(height: UsSpacing.xl),
              _RecentSalesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewListingButton extends StatelessWidget {
  const _NewListingButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
      child: ShadButton(
        width: double.infinity,
        onPressed: () => context.push(UsRoutes.listingEditor),
        child: const Text('＋ NEW LISTING'),
      ),
    );
  }
}

/// ACTIVE / AWAITING / SOLD — the three numbers a seller checks first.
class _StatsStrip extends SignalWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SellDashboardViewModel>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StatCell(
                  value: '${model.activeCount.value}',
                  label: 'ACTIVE',
                  highlight: true,
                ),
              ),
              const _Divider(),
              Expanded(
                child: _StatCell(
                  value: '${model.reserved.value.length}',
                  label: 'AWAITING',
                ),
              ),
              const _Divider(),
              Expanded(
                child: _StatCell(
                  value: '${model.soldCount.value}',
                  label: 'SOLD',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.h1Large.copyWith(
              color: highlight ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMd.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(width: 2, color: theme.colorScheme.foreground);
  }
}

/// Reserved listings — the actionable strip: these have a buyer waiting
/// on a handover, so they surface first with a nudge to mark them sold.
class _ReservedSection extends SignalWidget {
  const _ReservedSection();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SellDashboardViewModel>();
    final reserved = model.reserved.value;
    if (reserved.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
          child: Row(
            children: [
              Icon(
                LucideIcons.handshake,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text('AWAITING HANDOVER', style: theme.textTheme.labelSm),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final listing in reserved)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: UsSpacing.lg,
              vertical: UsSpacing.xs,
            ),
            child: _ReservedCard(listing: listing),
          ),
      ],
    );
  }
}

class _ReservedCard extends StatelessWidget {
  const _ReservedCard({required this.listing});

  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: () async {
        // Marking sold (or unreserving) inside the detail page changes the
        // status; the dashboard re-syncs when the tab is shown again.
        await context.push(UsRoutes.listingDetailsRoute(listing.id));
        di<SellDashboardViewModel>().refresh();
      },
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Text(
          listing.title,
          style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          LucideIcons.chevronRight,
          color: theme.colorScheme.mutedForeground,
        ),
        child: Text(
          'A buyer is waiting — arrange the meetup, then mark it sold.',
          style: theme.textTheme.muted,
        ),
      ),
    );
  }
}

/// The seller's listings, first page — a glanceable grid with the full
/// management surface one tap away.
class _MyListingsSection extends SignalWidget {
  const _MyListingsSection();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SellDashboardViewModel>();
    final listings = model.listings.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('MY LISTINGS', style: theme.textTheme.labelSm),
              if (listings.isNotEmpty)
                GestureDetector(
                  onTap: () => context.push(UsRoutes.myListings),
                  child: Text(
                    'SEE ALL',
                    style: theme.textTheme.labelSm.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (listings.isEmpty)
          const _EmptyHint(
            icon: LucideIcons.packageOpen,
            message: 'Nothing listed yet. Tap ＋ NEW LISTING to start selling.',
          )
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(width: UsSpacing.md),
              itemBuilder: (context, index) {
                final listing = listings[index];
                return SizedBox(
                  width: 160,
                  child: GestureDetector(
                    onTap: () => context.push(
                      UsRoutes.listingDetailsRoute(listing.id),
                    ),
                    child: ListingCard(listing: listing),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Recent sales with earnings — the reward side of the dashboard.
class _RecentSalesSection extends SignalWidget {
  const _RecentSalesSection();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SellDashboardViewModel>();
    final sales = model.sales.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RECENT SALES', style: theme.textTheme.labelSm),
              if (model.earningsMinor.value > 0)
                Text(
                  'EARNED ₦${_formatAmount(model.earningsMinor.value)}',
                  style: theme.textTheme.labelSm.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (sales.isEmpty)
          const _EmptyHint(
            icon: LucideIcons.shoppingBag,
            message: 'No sales yet. Your completed deals will show up here.',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final sale in sales.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: UsSpacing.sm),
                    child: _SaleRow(sale: sale),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatAmount(int minor) {
    final major = minor / 100;
    return major == major.roundToDouble()
        ? major.round().toString()
        : major.toStringAsFixed(2);
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final price = sale.price;
    final subtitle = price == null
        ? 'Barter • ${timeago.format(sale.createdAt)}'
        : '₦${price.toInt()} • ${timeago.format(sale.createdAt)}';

    return GestureDetector(
      onTap: () => context.push(UsRoutes.listingDetailsRoute(sale.listingId)),
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Text(
          sale.listingTitle,
          style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          LucideIcons.check,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        child: Text(subtitle, style: theme.textTheme.muted),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UsSpacing.lg),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.mutedForeground),
          const SizedBox(height: UsSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.muted,
          ),
        ],
      ),
    );
  }
}
