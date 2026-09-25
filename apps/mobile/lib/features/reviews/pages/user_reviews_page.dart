import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/reviews/data/reviews_repository.dart';
import 'package:uni_stash_mobile/features/reviews/models/reviews_models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// USER REVIEWS (rating wall): every review a user has received, with
/// their average + count. Reached from a user's profile / seller card.
class UserReviewsPage extends StatefulWidget {
  const UserReviewsPage({
    required this.userId,
    required this.userName,
    super.key,
  });

  final String userId;
  final String userName;

  @override
  State<UserReviewsPage> createState() => _UserReviewsPageState();
}

class _UserReviewsPageState extends State<UserReviewsPage> {
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'userReviews-${widget.userId}',
      init: (getIt) {
        getIt.registerLazySingleton<UserReviewsViewModel>(
          () => UserReviewsViewModel(di<ReviewsRepository>(), widget.userId),
          dispose: (model) => model.dispose(),
        );
      },
    );
    di<UserReviewsViewModel>().fetch();
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
    return UsPage(
      gutters: const .all(16),
      header: UsPageHeader(
        title: Text(
          'REVIEWS',
          overflow: .ellipsis,
        ),
      ),
      body: const _ReviewsBody(),
    );
  }
}

/// Page-scoped loader for one user's reviews.
class UserReviewsViewModel {
  UserReviewsViewModel(this._repository, this.userId);

  final ReviewsRepository _repository;
  final String userId;

  final summary = signal<UserReviewsResponse?>(null);
  final isLoading = signal(false);
  final error = signal<String?>(null);

  Future<void> fetch() async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.forUser(userId);
    switch (result) {
      case Success(:final value):
        summary.value = value;
      case Failure(:final message):
        error.value = message;
    }
    isLoading.value = false;
  }

  void dispose() {
    summary.dispose();
    isLoading.dispose();
    error.dispose();
  }
}

class _ReviewsBody extends SignalWidget {
  const _ReviewsBody();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<UserReviewsViewModel>();
    final summary = model.summary.value;
    final isLoading = model.isLoading.value;
    final error = model.error.value;

    if (isLoading && summary == null) {
      return const Center(child: Spinner());
    }

    if (error != null && summary == null) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(error, style: theme.textTheme.muted, textAlign: .center),
            const SizedBox(height: 16),
            ShadButton.outline(onPressed: model.fetch, child: const Text('RETRY')),
          ],
        ),
      );
    }

    final reviews = summary?.reviews ?? const <Review>[];
    if (reviews.isEmpty) {
      return Center(
        child: Text(
          'No reviews yet',
          style: theme.textTheme.muted,
        ),
      );
    }

    final average = summary?.averageRating;
    return ListView(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: .center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(
                      LucideIcons.star,
                      size: 20,
                      color: average != null && i <= average.round()
                          ? theme.colorScheme.primary
                          : theme.colorScheme.mutedForeground,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                average == null
                    ? '${summary?.reviewCount ?? 0} reviews'
                    : '${average.toStringAsFixed(1)} • ${summary!.reviewCount} reviews',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final review in reviews) _ReviewTile(review: review),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const .only(bottom: 8),
      child: ShadCard(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              review.authorName,
              style: theme.textTheme.p.copyWith(fontWeight: .w600),
            ),
          ),
          for (var i = 1; i <= 5; i++)
            Icon(
              LucideIcons.star,
              size: 14,
              color: i <= review.rating
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          if (review.comment != null && review.comment!.isNotEmpty)
            Text(review.comment!, style: theme.textTheme.small),
          const SizedBox(height: 4),
          Text(
            '${review.listingTitle} • ${timeago.format(review.createdAt)}',
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
