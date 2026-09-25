import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/features/blocks/data/blocks_repository.dart';
import 'package:uni_stash_mobile/features/blocks/models/models.dart';
import 'package:uni_stash_mobile/features/blocks/view_models/blocked_users_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// Settings → BLOCKED USERS: the caller's block list with unblock.
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  late final BlockedUsersViewModel _model;
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'blockedUsersPage',
      init: (getIt) {
        getIt.registerLazySingleton<BlockedUsersViewModel>(
          () => BlockedUsersViewModel(di<BlocksRepository>()),
        );
      },
    );
    _model = di<BlockedUsersViewModel>();
    unawaited(_model.fetch());
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
    return const UsPage(
      header: UsPageHeader(title: Text('BLOCKED USERS')),
      body: _Body(),
    );
  }
}

class _Body extends SignalHookWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<BlockedUsersViewModel>();

    if (model.isLoading.value) return const Center(child: Spinner());

    final error = model.error.value;
    final users = model.blockedUsers.value;
    if (error != null && users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
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

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              LucideIcons.userX,
              size: 48,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              'You have not blocked anyone.',
              style: theme.textTheme.muted,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(UsSpacing.lg),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: UsSpacing.sm),
      itemBuilder: (context, index) => _BlockedUserTile(user: users[index]),
    );
  }
}

class _BlockedUserTile extends SignalHookWidget {
  const _BlockedUserTile({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<BlockedUsersViewModel>();
    final busy = model.busyUserId.value == user.blockedId;

    return ShadCard(
      padding: const .symmetric(
        horizontal: UsSpacing.md,
        vertical: UsSpacing.md,
      ),
      child: Row(
        children: [
          UsAvatar(name: user.displayName, photoUrl: user.photoUrl, size: 36),
          const SizedBox(width: UsSpacing.md),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.small.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ShadButton.outline(
            onPressed: busy ? null : () => unawaited(model.unblock(user)),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: Spinner(),
                  )
                : const Text('UNBLOCK'),
          ),
        ],
      ),
    );
  }
}
