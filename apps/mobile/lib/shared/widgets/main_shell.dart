import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/notifications/in_app_chat_notifier.dart';
import 'package:uni_stash_mobile/core/user/user_view_model.dart';
import 'package:uni_stash_mobile/features/chats/data/_data.dart';
import 'package:uni_stash_mobile/features/chats/view_models/_view_models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class MainShell extends StatefulWidget {
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

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  /// Session-lived bridge: user-channel subscription, live thread refresh,
  /// in-app notifications for messages in chats the user isn't viewing.
  late final ChatRealtimeCoordinator _chatRealtime;
  late final InAppChatNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = di<InAppChatNotifier>();
    // The notifier renders through ShadToaster, installed above the app's
    // navigator — this shell context can reach it.
    _notifier.attach(context);
    _chatRealtime = ChatRealtimeCoordinator(
      realtimeClient: di<RealtimeClient>(),
      threads: di<ChatThreadsViewModel>(),
      notifier: _notifier,
      currentUserId: di<UserViewModel>().currentUser.value?.id ?? '',
      logger: di<Logger>(),
    );
    _chatRealtime.start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatRealtime.stop();
    _notifier.detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The OS may have killed the socket while dozed — re-check it.
      _chatRealtime.onAppResumed();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      body: widget.navigationShell,
      gutters: .zero,
      resizeToAvoidBottomInset: false,
      footer: SignalBuilder(
        builder: (context) {
          // Unread badge on the CHAT tab, driven by the shared
          // ChatThreadsViewModel (guide 7.7).
          final hasUnread = di<ChatThreadsViewModel>().unreadCount.value > 0;
          return UsBottomNavBar(
            destinations: MainShell.destinations,
            currentIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            badgedIndices: hasUnread
                ? const {MainShell.chatTabIndex}
                : const {},
          );
        },
      ),
    );
  }
}
