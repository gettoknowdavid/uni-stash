import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/listings/data/_data.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/_view_models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/condition_badge.dart';
import 'package:uni_stash_mobile/features/listings/widgets/status_badge.dart';
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
    unawaited(di.popScope());
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
          const Positioned(
            left: 16,
            top: 16,
            child: UsBackButton(size: 30),
          ),
          const Positioned(
            right: 16,
            top: 16,
            child: _BookmarkButton(size: 30),
          ),
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
        final model = di<ListingDetailViewModel>();
        final detail = model.detail.value;
        final isLoading = model.isLoading.value;
        final error = model.error.value;

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
                onRetry: () => model.fetch(id),
              ),
            ),
          );
        }

        if (detail == null) {
          return const UsPage(
            body: Center(child: Text('Listing not found')),
          );
        }

        final date = timeago.format(detail.createdAt);

        return UsPage(
          gutters: .zero,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
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
                    child: Icon(
                      LucideIcons.image,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const .symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: .spaceBetween,
                    children: [
                      StatusBadge(status: detail.status),
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
                    detail.title,
                    style: theme.textTheme.h1,
                    overflow: .ellipsis,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const .symmetric(horizontal: 16),
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.small,
                      children: [
                        TextSpan(text: 'Listed $date'),
                        const TextSpan(text: ' • '),
                        TextSpan(text: detail.category.label),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const .symmetric(horizontal: 16),
                  child: Text(
                    'CONDITION',
                    style: theme.textTheme.labelSm,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: .centerLeft,
                  child: Padding(
                    padding: const .symmetric(horizontal: 16),
                    child: ConditionBadge(condition: detail.condition),
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
                ShadSeparator.horizontal(
                  thickness: 2,
                  margin: const .symmetric(horizontal: 16),
                  color: theme.colorScheme.borderStrong,
                ),
                const SizedBox(height: 24),
                ShadSeparator.horizontal(
                  thickness: 2,
                  margin: const .symmetric(horizontal: 16),
                  color: theme.colorScheme.borderStrong,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({this.size = 40});
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
