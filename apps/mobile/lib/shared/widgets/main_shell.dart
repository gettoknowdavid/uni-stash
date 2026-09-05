import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class MainShell extends StatelessWidget {
  const MainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<UsNavDestination> destinations = [
    UsNavDestination(label: 'HOME', icon: LucideIcons.home),
    UsNavDestination(label: 'SEARCH', icon: LucideIcons.search),
    UsNavDestination(label: 'SELL', icon: LucideIcons.circlePlus),
    UsNavDestination(label: 'CHAT', icon: LucideIcons.messageCircle),
    UsNavDestination(label: 'PROFILE', icon: LucideIcons.circleUser),
  ];

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      body: navigationShell,
      resizeToAvoidBottomInset: false,
      footer: UsBottomNavBar(
        destinations: destinations,
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }
}
