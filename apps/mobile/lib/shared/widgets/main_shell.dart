import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/chats/view_models/_view_models.dart';
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

  /// Index of the CHAT destination in [destinations].
  static const int chatTabIndex = 3;

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
      gutters: .zero,
      resizeToAvoidBottomInset: false,
      footer: SignalBuilder(
        builder: (context) {
          // Unread badge on the CHAT tab, driven by the shared
          // ChatThreadsViewModel (guide 7.7).
          final hasUnread = di<ChatThreadsViewModel>().unreadCount.value > 0;
          return UsBottomNavBar(
            destinations: destinations,
            currentIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            badgedIndices: hasUnread ? const {chatTabIndex} : const {},
          );
        },
      ),
    );
  }
}
