import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Horizontal "ALL + categories" chip row shared by the Home feed and the
/// Search page. Pure presentation — callers own the selection signal.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  final List<Category> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _CategoryChip(
        label: 'ALL',
        selected: selectedCategoryId == null,
        onTap: () => onSelected(null),
      ),
      for (final cat in categories)
        _CategoryChip(
          label: cat.label.toUpperCase(),
          selected: selectedCategoryId == cat.id,
          onTap: () => onSelected(cat.id),
        ),
    ];

    return SizedBox(
      height: 24,
      child: ListView.separated(
        scrollDirection: .horizontal,
        padding: const .symmetric(horizontal: UsSpacing.lg),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: UsSpacing.sm),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: ShadCard(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.card,
        border: selected
            ? .none
            : .all(color: theme.colorScheme.border, width: 1),
        padding: const .symmetric(horizontal: UsSpacing.lg),
        rowCrossAxisAlignment: .center,
        child: Text(
          label,
          style: theme.textTheme.labelSm.copyWith(
            color: selected
                ? theme.colorScheme.primaryForeground
                : theme.colorScheme.foreground,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
