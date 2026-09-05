import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// A single destination (icon + label) in a [UsBottomNavBar].
class UsNavDestination {
  const UsNavDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  /// The destination label, rendered uppercase in the mono typeface.
  final String label;

  /// The icon shown when the destination is not selected.
  final IconData icon;

  /// Optional alternate icon shown when the destination is selected.
  final IconData? selectedIcon;
}

/// Bottom navigation bar for the app.
class UsBottomNavBar extends StatelessWidget {
  const UsBottomNavBar({
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  /// The height of the navigation bar itself (excluding safe area insets).
  static const double height = 64;

  /// The destinations to display in the navigation bar.
  final List<UsNavDestination> destinations;

  /// The index of the currently selected destination.
  final int currentIndex;

  /// The callback invoked when a destination is selected.
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _UsNavBarItem(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  onTap: () => onDestinationSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UsNavBarItem extends StatelessWidget {
  const _UsNavBarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final UsNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: GestureDetector(
        behavior: .opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 3,
              width: double.infinity,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.transparent,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: .center,
                children: [
                  Icon(
                    selected
                        ? (destination.selectedIcon ?? destination.icon)
                        : destination.icon,
                    size: 24,
                    color: color,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    style: theme.textTheme.labelSm.copyWith(
                      color: color,
                      letterSpacing: 0.6,
                      fontWeight: selected ? .w700 : .w400,
                      decoration: .none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
