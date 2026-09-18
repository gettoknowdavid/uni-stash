import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/profile/pages/logout_dialog.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(title: Text('SETTINGS')),
      body: SingleChildScrollView(
        padding: const .symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            const _SectionCard(
              headerLabel: 'ACCOUNT',
              children: [
                _SettingsRow(
                  label: 'Email',
                  subtitle: 'adaeze.b@uniport.edu.ng',
                  trailing: _Chevron(),
                ),
                _SettingsRow(
                  label: 'Phone',
                  subtitle: '+234 *** *** 1234',
                  trailing: _Chevron(),
                ),
                _SettingsRow(
                  label: 'Change Password',
                  trailing: _Chevron(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionCard(
              headerLabel: 'NOTIFICATIONS',
              children: [
                _SettingsRow(
                  label: 'Push Notifications',
                  subtitle: 'Alerts for new messages and offers',
                  trailing: UsSwitch(value: true),
                ),
                _SettingsRow(
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
            const _SectionCard(
              headerLabel: 'LEGAL',
              children: [
                _SettingsRow(
                  label: 'Terms of Service',
                  trailing: _ExternalLink(),
                ),
                _SettingsRow(
                  label: 'Privacy Policy',
                  trailing: _ExternalLink(),
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
      // Adding this padding to the right of the card to ensure the
      // brutalist border shows. Should have been fixed by the setting
      // `clipBehavior: Clip.none` in the top level `SingleChildScrollView`.
      // but it caused unexpected overlapping for the header.
      // Will find a better solution later
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
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
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

class _ExternalLink extends StatelessWidget {
  const _ExternalLink();

  @override
  Widget build(BuildContext context) {
    return Icon(
      LucideIcons.externalLink,
      size: 20,
      color: ShadTheme.of(context).colorScheme.mutedForeground,
    );
  }
}
