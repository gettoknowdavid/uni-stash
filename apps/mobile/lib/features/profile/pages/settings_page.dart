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
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            const _SectionHeader(label: 'ACCOUNT'),
            const _SettingsRow(
              label: 'Email',
              trailing: _Chevron(),
            ),
            const _SettingsRow(
              label: 'Phone',
              trailing: _Chevron(),
            ),
            const _SettingsRow(
              label: 'Change Password',
              trailing: _Chevron(),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(label: 'NOTIFICATIONS'),
            _SettingsRow(
              label: 'Push Notifications',
              description: 'Alerts for new messages and offers',
              trailing: ShadSwitch(
                value: true,
                onChanged: (_) {},
              ),
            ),
            _SettingsRow(
              label: 'Email Notifications',
              description: 'Weekly digests and major updates',
              trailing: ShadSwitch(
                value: false,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(label: 'PRIVACY'),
            _SettingsRow(
              label: 'Profile Visibility',
              description: 'Allow others to see my listings history',
              trailing: ShadSwitch(
                value: true,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(label: 'LEGAL'),
            const _SettingsRow(
              label: 'Terms of Service',
              trailing: _ExternalLink(),
            ),
            const _SettingsRow(
              label: 'Privacy Policy',
              trailing: _ExternalLink(),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const .symmetric(horizontal: 16),
              child: ShadButton.destructive(
                width: double.infinity,
                onPressed: () => _showLogoutDialog(context),
                child: const Text('LOG OUT'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

Future<void> _showLogoutDialog(BuildContext context) {
  return showShadDialog<void>(
    context: context,
    builder: (context) => const LogoutDialog(),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      child: Text(
        label,
        style: theme.textTheme.labelSm.copyWith(
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.description,
    this.trailing,
  });

  final String label;
  final String? description;
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
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: theme.textTheme.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
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
