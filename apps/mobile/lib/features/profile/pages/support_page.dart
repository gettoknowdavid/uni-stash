import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// SUPPORT (profile menu): contact channels + quick answers. There is no
/// support backend yet, so this is informational — email links open the
/// device mail client.
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _supportEmail = 'support@uni-stash.com';

  Future<void> _sendEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('UniStash Support')}',
    );
    final launched = await canLaunchUrl(uri);
    if (!context.mounted) return;
    if (launched) {
      await launchUrl(uri);
    } else {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          title: Text('No email app'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return UsPage(
      header: const UsPageHeader(title: Text('SUPPORT')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            const SizedBox(height: UsSpacing.lg),
            Icon(
              LucideIcons.headset,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              'We are here to help',
              textAlign: .center,
              style: theme.textTheme.h3,
            ),
            const SizedBox(height: UsSpacing.xs),
            Text(
              'Report a problem, ask a question or give feedback.',
              textAlign: .center,
              style: theme.textTheme.muted,
            ),
            const SizedBox(height: UsSpacing.xl),
            _SupportCard(
              icon: LucideIcons.mail,
              title: 'EMAIL US',
              subtitle: _supportEmail,
              onTap: () => _sendEmail(context),
            ),
            const SizedBox(height: UsSpacing.md),
            const _FaqCard(),
            const SizedBox(height: UsSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(width: UsSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelSm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.muted),
                ],
              ),
            ),
            Icon(
              LucideIcons.arrowRight,
              size: 20,
              color: theme.colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard();

  static const _faqs = <(String, String)>[
    (
      'How do I sell an item?',
      'Tap the SELL tab, add photos, set a price or barter request and '
          'publish. You can edit or mark listings sold from MY LISTINGS.',
    ),
    (
      'How do payments work?',
      'UniStash does not handle payments. Buyers pay sellers directly '
          '(cash or transfer) at your agreed meetup point.',
    ),
    (
      'Someone reserved my listing — now what?',
      'You will get a chat message from the buyer. Agree on a time and '
          'place, then mark the listing sold once the handover is done. '
          'Reservations expire automatically if the buyer does not confirm.',
    ),
    (
      'Why can I not reserve an item?',
      'Your student email must be verified first. Check SETTINGS for your '
          'verification status.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text('QUICK ANSWERS', style: theme.textTheme.labelSm),
          const SizedBox(height: UsSpacing.md),
          for (final (question, answer) in _faqs) ...[
            Text(
              question,
              style: theme.textTheme.p.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(answer, style: theme.textTheme.muted),
            const SizedBox(height: UsSpacing.md),
          ],
        ],
      ),
    );
  }
}
