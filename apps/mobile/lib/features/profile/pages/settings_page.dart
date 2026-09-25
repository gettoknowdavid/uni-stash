import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/notifications/push_notifications.dart';
import 'package:uni_stash_mobile/features/profile/pages/change_password_dialog.dart';
import 'package:uni_stash_mobile/features/profile/pages/logout_dialog.dart';
import 'package:uni_stash_mobile/features/profile/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final ProfileViewModel _model;

  @override
  void initState() {
    super.initState();
    _model = di<ProfileViewModel>();
    // Ensure profile is loaded for real data
    if (_model.profile.value == null) {
      _model.fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('SETTINGS')),
      body: _SettingsBody(model: _model),
    );
  }
}

class _SettingsBody extends SignalWidget {
  const _SettingsBody({required this.model});

  final ProfileViewModel model;

  @override
  Widget build(BuildContext context) {
    final profile = model.profile.value;
    final email = profile?.email ?? '—';
    final displayName = profile?.displayName ?? '—';

    return SingleChildScrollView(
      padding: const .symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          _SectionCard(
            headerLabel: 'ACCOUNT',
            children: [
              _SettingsRow(
                label: 'Email',
                subtitle: email,
              ),
              _SettingsRow(
                label: 'Name',
                subtitle: displayName,
                trailing: const _Chevron(),
                onTap: () => context.push(UsRoutes.editProfile),
              ),
              _SettingsRow(
                label: 'Change Password',
                trailing: const _Chevron(),
                onTap: () => unawaited(showShadDialog(
                  context: context,
                  builder: (context) => const ChangePasswordDialog(),
                )),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionCard(
            headerLabel: 'NOTIFICATIONS',
            children: [
              _SettingsRow(
                label: 'Push Notifications',
                subtitle: 'Alerts for new messages and offers',
                trailing: SignalBuilder(
                  builder: (context) {
                    final push = di<PushNotifications>();
                    return UsSwitch(
                      value: push.enabled.value,
                      onChanged: (value) =>
                          unawaited(_setPushEnabled(context, value)),
                    );
                  },
                ),
              ),
              const _SettingsRow(
                label: 'Email Notifications',
                subtitle: 'Weekly digests and major updates',
                trailing: UsSwitch(value: false),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionCard(
            headerLabel: 'PRIVACY',
            children: [
              _SettingsRow(
                label: 'Profile Visibility',
                subtitle: 'Allow others to see my listings history',
                trailing: UsSwitch(value: true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionCard(
            headerLabel: 'LEGAL',
            children: [
              _SettingsRow(
                label: 'Terms & Conditions',
                trailing: const _Chevron(),
                onTap: () => context.push(UsRoutes.terms),
              ),
              _SettingsRow(
                label: 'Privacy Policy',
                trailing: const _Chevron(),
                onTap: () => context.push(UsRoutes.privacy),
              ),
            ],
          ),
          const SizedBox(height: 32),
          ShadButton.outline(
            child: const Text('LOG OUT'),
            onPressed: () => _showLogoutDialog(context),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Applies the push toggle and surfaces a failure without flipping the
/// switch back — the Beams SDK call is best-effort and the preference is
/// already persisted by the time this runs.
Future<void> _setPushEnabled(BuildContext context, bool value) async {
  final push = di<PushNotifications>();
  await push.setEnabled(value);
  if (!context.mounted) return;
  if (value && !push.isStarted) {
    ShadToaster.of(context).show(
      const ShadToast(
        title: Text('Push unavailable'),
        description: Text(
          'Notifications could not be enabled on this device.',
        ),
      ),
    );
  }
}

Future<void> _showLogoutDialog(BuildContext context) {
  return showShadDialog<bool>(
    context: context,
    builder: (context) => const LogoutDialog(),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.headerLabel,
    required this.children,
  });

  final String headerLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const .only(right: 2),
      child: ShadCard(
        padding: .zero,
        border: .all(color: UsPrimitives.neutral900, width: 2),
        shadows: UsElevation.brutalist,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(
              padding: const .symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.muted,
              child: Text(
                headerLabel,
                style: theme.textTheme.labelSm.copyWith(
                  color: theme.colorScheme.mutedForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.p.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.small.copyWith(
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ShadSeparator.horizontal(
            margin: .zero,
            color: theme.colorScheme.border,
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return Icon(
      LucideIcons.chevronRight,
      size: 20,
      color: ShadTheme.of(context).colorScheme.mutedForeground,
    );
  }
}
