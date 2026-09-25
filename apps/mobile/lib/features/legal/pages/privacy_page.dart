import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// PRIVACY POLICY — aligned with the Nigeria Data Protection Act 2023
/// (NDPA), Google Play's User Data policy and Apple's App privacy
/// guidelines: what we collect, why, what we never do, your rights and
/// how to exercise them.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      header: UsPageHeader(title: Text('PRIVACY POLICY')),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Meta(),
            SizedBox(height: 24),
            _Section(
              title: '1. Who we are',
              body:
                  'UniStash is a campus marketplace for verified students '
                  'in Nigeria. For the purposes of the Nigeria Data '
                  'Protection Act 2023 (NDPA), UniStash is the data '
                  'controller of your personal data. Contact '
                  'support@uni-stash.com for any privacy matter.',
            ),
            _Section(
              title: '2. Data we collect',
              body: 'We collect only what the marketplace needs to work:',
              bullets: [
                '''Account data: your school email, display name, school, and optional profile photo''',
                '''Verification status: whether your school email has been verified''',
                '''Listing data: the items, prices, descriptions and photos you post''',
                '''Chat messages: conversations between you and other users about a listing (including read receipts)''',
                '''Trading records: reservations and completed sales (who bought/sold what, and when)''',
                '''Device data: your device push-notification token, so we can alert you about messages and offers''',
                '''Saved items and searches: your bookmarks and recent search terms''',
              ],
            ),
            _Section(
              title: '3. What we do NOT collect',
              body:
                  'We do not collect or store payment card or bank account '
                  'details, we do not track your location, and we do not '
                  'buy or sell your personal data to data brokers or '
                  'advertisers. There are no third-party advertising SDKs '
                  'in the app.',
            ),
            _Section(
              title: '4. Why we use your data (lawful bases)',
              body: 'Under the NDPA we rely on:',
              bullets: [
                '''Contract — to run your account, listings, chats and trading history''',
                '''Legitimate interest — to keep the community safe: verifying school emails, handling reports, preventing fraud and abuse''',
                '''Consent — for push notifications, which you can switch off any time in Settings''',
                '''Legal obligation — where Nigerian law requires us to retain or disclose data''',
              ],
            ),
            _Section(
              title: '5. Who we share with',
              body:
                  'Other users see your display name, school, verification '
                  'badge and (if set) photo — never your email or phone '
                  'number. Service providers under contract (hosting, '
                  'email delivery for OTPs, push notifications and '
                  'realtime messaging via Pusher) process data only to '
                  'run the service. We disclose data to law enforcement '
                  'only on a valid legal request under Nigerian due '
                  'process.',
            ),
            _Section(
              title: '6. How long we keep data',
              body:
                  'Account data is kept while your account is active. When '
                  'you delete your account there is a 30-day grace period, '
                  'after which your account is permanently deleted and '
                  'chats and personal data are removed. Aggregated, '
                  'anonymized statistics may be retained. Reports you '
                  'file may be kept as moderation records.',
            ),
            _Section(
              title: '7. Security',
              body:
                  'Passwords are stored only as salted hashes, traffic is '
                  'encrypted in transit (TLS), access to production data '
                  'is restricted, and email verification with OTP protects '
                  'account recovery. No system is perfectly secure; if a '
                  'breach affects you, we will notify you and the Nigeria '
                  'Data Protection Commission as the NDPA requires.',
            ),
            _Section(
              title: '8. Your rights',
              body:
                  'Under the NDPA you can request access to your data, '
                  'correction of inaccurate data, deletion of your data, '
                  'restriction of processing, and portability of data you '
                  'provided. You can object to processing based on '
                  'legitimate interest. You may withdraw consent (e.g. '
                  'push) at any time without affecting earlier processing.',
            ),
            _Section(
              title: '9. Exercising your rights',
              body:
                  'Use in-app controls first: edit your profile, delete '
                  'listings, toggle push, or delete your account entirely '
                  '(Settings → Danger Zone). For anything else, email '
                  'support@uni-stash.com and we will respond within 30 '
                  'days as the NDPA requires. You may also complain to '
                  'the Nigeria Data Protection Commission (NDPC).',
            ),
            _Section(
              title: '10. Children',
              body:
                  'UniStash is for students of partner universities and is '
                  'not directed at children under 13. We do not knowingly '
                  'collect data from children; if we learn of such an '
                  'account it will be deleted.',
            ),
            _Section(
              title: '11. Changes',
              body:
                  'We may update this policy; material changes will be '
                  'announced in the app and the date above will change.',
            ),
            SizedBox(height: 24),
            _FooterNote(),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      'Last updated: 25 September 2026 • Version 1.0',
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  final String title;
  final String body;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.p),
          for (final bullet in bullets) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(bullet, style: theme.textTheme.p)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      'Data protection contact: support@uni-stash.com',
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}
