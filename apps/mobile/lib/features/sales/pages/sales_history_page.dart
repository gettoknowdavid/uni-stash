import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart'
    show Currency;
import 'package:uni_stash_mobile/features/reviews/pages/rate_sale_dialog.dart';
import 'package:uni_stash_mobile/features/sales/data/_data.dart';
import 'package:uni_stash_mobile/features/sales/models/models.dart';
import 'package:uni_stash_mobile/features/sales/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Items the current user bought (guide 6.9).
class MyPurchasesPage extends StatelessWidget {
  const MyPurchasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SalesHistoryPage(
      kind: SalesKind.purchases,
      baseName: 'myPurchases',
      title: 'MY PURCHASES',
      emptyMessage: 'No purchases yet',
    );
  }
}

/// Items the current user sold (guide 6.10).
class MySalesPage extends StatelessWidget {
  const MySalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SalesHistoryPage(
      kind: SalesKind.sales,
      baseName: 'mySales',
      title: 'MY SALES',
      emptyMessage: 'No sales yet',
    );
  }
}

/// Shared cursor-paginated sale-history screen backing both entry points.
///
/// Registers a page-scoped [SalesViewModel] in `initState` and pops the
/// GetIt scope in `dispose`, following the auth/listings page pattern.
class _SalesHistoryPage extends StatefulWidget {
  const _SalesHistoryPage({
    required this.kind,
    required this.baseName,
    required this.title,
    required this.emptyMessage,
  });

  final SalesKind kind;
  final String baseName;
  final String title;
  final String emptyMessage;

  @override
  State<_SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<_SalesHistoryPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: widget.baseName,
      init: (getIt) {
        getIt.registerLazySingleton<SalesViewModel>(
          () => SalesViewModel(di<SalesRepository>(), kind: widget.kind),
          dispose: (model) => model.dispose(),
        );
      },
    );
    di<SalesViewModel>().fetch();
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
    return UsPage(
      gutters: const .all(16),
      header: UsPageHeader(title: Text(widget.title)),
      body: Column(
        children: [
          const SizedBox(height: UsSpacing.md),
          UsNoticeCard(
            variant: widget.kind == SalesKind.purchases
                ? UsNoticeVariant.warning
                : UsNoticeVariant.info,
            title: widget.kind == SalesKind.purchases
                ? 'BUYER REMINDER'
                : 'SELLER REMINDER',
            description: widget.kind == SalesKind.purchases
                ? 'If a purchase goes wrong, report the listing and contact '
                    'support. Always confirm items before payment.'
                : 'Hand over items only after payment is confirmed. Meet in '
                    'public campus locations.',
          ),
          const SizedBox(height: UsSpacing.md),
          Expanded(child: _SalesBody(emptyMessage: widget.emptyMessage)),
        ],
      ),
    );
  }
}

class _SalesBody extends SignalWidget {
  const _SalesBody({required this.emptyMessage});

  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<SalesViewModel>();
    final sales = model.sales.value;
    final isLoading = model.isLoading.value;
    final isLoadingMore = model.isLoadingMore.value;
    final error = model.error.value;

    if (isLoading && sales.isEmpty) {
      return const Center(child: Spinner());
    }

    if (error != null && sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

    if (sales.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: theme.textTheme.muted),
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
      child: ListView.builder(
        itemCount: sales.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == sales.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Spinner()),
            );
          }
          return _SaleTile(sale: sales[index]);
        },
      ),
    );
  }
}

/// Shared tile for both histories: title, price/barter + relative date,
/// tapping opens the listing detail.
class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});

  final Sale sale;

  String get _subtitle {
    final date = timeago.format(sale.createdAt);
    final price = sale.price;
    if (price == null) return 'Barter • $date';
    final symbol = Currency.fromCode(sale.currency ?? 'NGN').symbol;
    final amount = price == price.roundToDouble() ? price.toInt() : price;
    return '$symbol$amount • $date';
  }

  /// The other party in this sale — the rate target for the given sale.
  /// Null when the sale had no recorded buyer (walk-up sale by this user).
  String? get _counterpartId {
    final myId = di<UserViewModel>().currentUser.value?.id;
    if (myId == null) return null;
    if (sale.buyerId == myId) return sale.sellerId;
    if (sale.sellerId == myId) return sale.buyerId;
    return null;
  }

  Future<void> _rate(BuildContext context) async {
    await showShadDialog<bool>(
      context: context,
      builder: (context) => RateSaleDialog(saleId: sale.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return GestureDetector(
      onTap: () async {
        await context.push(UsRoutes.listingDetailsRoute(sale.listingId));
      },
      child: ShadCard(
        title: Text(
          sale.listingTitle,
          style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
        ),
        padding: const .symmetric(horizontal: 16, vertical: 12),
        trailing: Icon(
          LucideIcons.chevronRight,
          color: theme.colorScheme.mutedForeground,
        ),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(_subtitle, style: theme.textTheme.muted),
            if (_counterpartId != null) ...[
              const SizedBox(height: 8),
              ShadButton.outline(
                height: 28,
                padding: const .symmetric(horizontal: 12),
                onPressed: () => _rate(context),
                child: const Text('RATE SALE'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
