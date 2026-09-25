import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/reviews/data/reviews_repository.dart';
import 'package:uni_stash_mobile/features/reviews/models/reviews_models.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';

/// RATE THIS SALE dialog: 1–5 star picker + optional comment. Submits
/// `POST /reviews/{sale_id}`; the reviewee is always the sale counterpart.
class RateSaleDialog extends SignalHookWidget {
  const RateSaleDialog({required this.saleId, super.key});

  final String saleId;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final rating = useSignal(0);
    final comment = useSignal('');
    final isLoading = useSignal(false);
    final error = useSignal<String?>(null);

    Future<void> submit() async {
      if (rating.value == 0) {
        error.value = 'Tap the stars to choose a rating.';
        return;
      }

      isLoading.value = true;
      error.value = null;

      final result = await di<ReviewsRepository>().create(
        saleId,
        CreateReviewRequest(
          rating: rating.value,
          comment: comment.value.trim().isEmpty ? null : comment.value.trim(),
        ),
      );
      isLoading.value = false;

      switch (result) {
        case Success():
          if (context.mounted) {
            context.pop(true);
            ShadToaster.of(context).show(
              const ShadToast(
                title: Text('Review submitted'),
                description: Text('Thanks for rating your trade partner.'),
              ),
            );
          }
        case Failure(:final message):
          error.value = message;
      }
    }

    return ShadDialog.alert(
      title: const Text('RATE THIS SALE'),
      titleStyle: theme.textTheme.h1,
      description: const Padding(
        padding: .only(bottom: 16),
        child: Text(
          'How did it go? Your rating helps keep the campus marketplace '
          'trustworthy. Reviews are public.',
        ),
      ),
      descriptionTextAlign: .left,
      actionsAxis: .horizontal,
      expandActionsWhenTiny: false,
      actions: [
        ShadButton.outline(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          onPressed: isLoading.value ? null : () => context.pop(false),
          child: const Text('CANCEL'),
        ),
        ShadButton(
          height: 30,
          padding: const .symmetric(horizontal: 12),
          enabled: !isLoading.value,
          onPressed: () => unawaited(submit()),
          child: isLoading.value ? const Spinner() : const Text('SUBMIT'),
        ),
      ],
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          SignalBuilder(
            builder: (context) => Row(
              mainAxisAlignment: .center,
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: () => rating.value = i,
                    child: Padding(
                      padding: const .all(4),
                      child: Icon(
                        i <= rating.value
                            ? LucideIcons.star
                            : LucideIcons.star,
                        size: 32,
                        color: i <= rating.value
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ShadInput(
            placeholder: const Text('Add a comment (optional)'),
            maxLines: 3,
            minLines: 2,
            onChanged: (v) => comment.value = v,
          ),
          if (error.value != null) ...[
            const SizedBox(height: 8),
            Text(
              error.value!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
