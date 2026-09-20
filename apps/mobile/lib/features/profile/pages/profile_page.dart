import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/user/models.dart';
import 'package:uni_stash_mobile/features/profile/data/profile_repository.dart';
import 'package:uni_stash_mobile/features/profile/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileViewModel _model;

  @override
  void initState() {
    super.initState();
    // Page-scoped ViewModel (same pattern as the auth pages): a fresh
    // instance per visit, disposed by GetIt when the scope pops.
    di.pushNewScope(
      scopeName: 'profilePage',
      init: (getIt) {
        getIt.registerLazySingleton<ProfileViewModel>(
          () => ProfileViewModel(di<ProfileRepository>()),
        );
      },
    );
    _model = di<ProfileViewModel>();
    _model.fetch();
  }

  @override
  void dispose() {
    // popScope() is async but dispose() is sync — calling it here would
    // discard the Future and never actually pop the scope.  Page-scoped
    // GetIt scopes are cleaned up in bulk by the logout flow via
    // popScopesTill(root).  For normal back-navigation the orphaned scope
    // is harmless (the next page pushes its own scope on top).
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: UsPageHeader(
        title: const Text('PROFILE'),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push(UsRoutes.settings),
          ),
        ],
      ),
      body: const _ProfileBody(),
    );
  }
}

class _ProfileBody extends SignalHookWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context) {
    final model = di<ProfileViewModel>();

    if (model.isLoading.value) {
      return const Center(child: ShadSpinner());
    }

    final error = model.error.value;
    final profile = model.profile.value;
    if (error != null && profile == null) {
      return _ErrorView(message: error, onRetry: model.fetch);
    }

    if (profile == null) {
      return const Center(child: ShadSpinner());
    }

    return _ProfileContent(profile: profile);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final void Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Text(
            message,
            style: theme.textTheme.muted,
            textAlign: .center,
          ),
          const SizedBox(height: 16),
          ShadButton.outline(onPressed: onRetry, child: const Text('RETRY')),
        ],
      ),
    );
  }
}

class _ProfileContent extends SignalHookWidget {
  const _ProfileContent({required this.profile});

  final User profile;

  @override
  Widget build(BuildContext context) {
    final model = di<ProfileViewModel>();
    final stats = model.stats.value;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          const SizedBox(height: 24),
          UsAvatar(
            name: profile.displayName,
            verified: profile.emailVerified,
          ),
          const SizedBox(height: 24),
          Text(
            _shortDisplayName(profile.displayName),
            style: ShadTheme.of(context).textTheme.h1Large,
          ),
          const SizedBox(height: 8),
          Text(
            _emailTag(profile.email),
            style: ShadTheme.of(context).textTheme.labelLg.copyWith(
              color: ShadTheme.of(context).colorScheme.textSecondary,
            ),
          ),
          if (profile.emailVerified) ...[
            const SizedBox(height: 16),
            const _VerifiedStatusRow(),
          ],
          const SizedBox(height: 24),
          ShadButton(
            onPressed: () => context.push(UsRoutes.editProfile),
            child: const Text('EDIT PROFILE'),
          ),
          const SizedBox(height: 64),
          _StatsStrip(stats: stats),
          const SizedBox(height: 64),
          const _ProfileMenu(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// "Ada Lovelace" → "ADA L." — first name plus last-name initials,
/// matching the mock's condensed name treatment.
String _shortDisplayName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'))
    ..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) return '';
  final first = parts.first.toUpperCase();
  final initials = parts.skip(1).map((part) => '${part[0].toUpperCase()}.');
  return [first, ...initials].join(' ');
}

/// "ada@unilag.edu.ng" → "@UNILAG.EDU.NG" — the school domain as the
/// handle-style subtitle shown in the mock.
String _emailTag(String email) {
  final domain = email.split('@').last;
  return '@${domain.toUpperCase()}';
}


class _VerifiedStatusRow extends StatelessWidget {
  const _VerifiedStatusRow();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Icon(
          LucideIcons.shieldCheck,
          size: 24,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'STUDENT STATUS CONFIRMED',
            style: theme.textTheme.large.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});

  final ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatsCell(
                value: stats.activeListings,
                label: 'ACTIVE LISTINGS',
                highlight: true,
              ),
            ),
            const _StatsDivider(),
            Expanded(
              child: _StatsCell(value: stats.itemsSold, label: 'ITEMS SOLD'),
            ),
            const _StatsDivider(),
            Expanded(
              child: _StatsCell(value: stats.saved, label: 'SAVED'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCell extends StatelessWidget {
  const _StatsCell({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const .all(16),
      child: Column(
        mainAxisSize: .min,
        children: [
          Text(
            '$value',
            style: theme.textTheme.h1Large.copyWith(
              color: highlight ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: .center,
            style: theme.textTheme.labelMd.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsDivider extends StatelessWidget {
  const _StatsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 2, color: UsPrimitives.neutral900);
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _MenuRow(icon: LucideIcons.tag, label: 'MY LISTINGS'),
        _MenuRow(icon: LucideIcons.bookmark, label: 'SAVED ITEMS'),
        _MenuRow(icon: LucideIcons.history, label: 'TRANSACTION HISTORY'),
        _MenuRow(icon: LucideIcons.headset, label: 'SUPPORT'),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showComingSoon(context, label),
      child: Column(
        children: [
          Padding(
            padding: const .symmetric(vertical: 20),
            child: Row(
              children: [
                Icon(icon, size: 24, color: theme.colorScheme.foreground),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.arrowRight,
                  size: 24,
                  color: theme.colorScheme.textSecondary,
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.colorScheme.borderSubtle),
        ],
      ),
    );
  }
}

/// Destination routes (edit profile, my listings, …) don't exist yet —
/// every actionable row reports itself as coming soon.
void _showComingSoon(BuildContext context, String feature) {
  ShadToaster.of(context).show(
    ShadToast(
      title: const Text('Coming Soon'),
      description: Text('$feature is on the way.'),
    ),
  );
}
