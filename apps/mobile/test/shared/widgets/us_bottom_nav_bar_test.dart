import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/us_bottom_nav_bar.dart';

import '../../helpers/test_helpers.dart';

void main() {
  const destinations = [
    UsNavDestination(label: 'HOME', icon: LucideIcons.home),
    UsNavDestination(label: 'SEARCH', icon: LucideIcons.search),
    UsNavDestination(label: 'SELL', icon: LucideIcons.circlePlus),
    UsNavDestination(label: 'CHAT', icon: LucideIcons.messageCircle),
    UsNavDestination(label: 'PROFILE', icon: LucideIcons.circleUser),
  ];

  Widget buildNavBar({
    required int currentIndex,
    ValueChanged<int>? onDestinationSelected,
    List<UsNavDestination> items = destinations,
  }) {
    return buildTestApp(
      child: UsBottomNavBar(
        destinations: items,
        currentIndex: currentIndex,
        onDestinationSelected: onDestinationSelected ?? (_) {},
      ),
    );
  }

  group('UsBottomNavBar', () {
    testWidgets('renders every destination label', (tester) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 0));

      for (final destination in destinations) {
        expect(find.text(destination.label), findsOneWidget);
      }
    });

    testWidgets('renders every destination icon', (tester) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 0));

      expect(find.byIcon(LucideIcons.home), findsOneWidget);
      expect(find.byIcon(LucideIcons.search), findsOneWidget);
      expect(find.byIcon(LucideIcons.circlePlus), findsOneWidget);
      expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleUser), findsOneWidget);
    });

    testWidgets('uses the selected icon variant for the active destination', (
      tester,
    ) async {
      const items = [
        UsNavDestination(
          label: 'HOME',
          icon: LucideIcons.home,
          selectedIcon: LucideIcons.building2,
        ),
        UsNavDestination(label: 'SEARCH', icon: LucideIcons.search),
      ];

      await tester.pumpWidget(buildNavBar(currentIndex: 0, items: items));

      expect(find.byIcon(LucideIcons.building2), findsOneWidget);
      expect(find.byIcon(LucideIcons.home), findsNothing);
    });

    testWidgets('highlights the selected destination with the primary color', (
      tester,
    ) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 2));

      final theme = ShadTheme.of(tester.element(find.text('SELL')));
      final selectedLabel = tester.widget<Text>(find.text('SELL'));
      final unselectedLabel = tester.widget<Text>(find.text('HOME'));

      expect(selectedLabel.style?.color, theme.colorScheme.primary);
      expect(selectedLabel.style?.fontWeight, FontWeight.w700);
      expect(unselectedLabel.style?.color, theme.colorScheme.mutedForeground);
      expect(unselectedLabel.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('reports the tapped destination index', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        buildNavBar(
          currentIndex: 0,
          onDestinationSelected: tapped.add,
        ),
      );

      await tester.tap(find.text('PROFILE'));
      expect(tapped, [4]);

      await tester.tap(find.text('CHAT'));
      expect(tapped, [4, 3]);
    });
  });
}
