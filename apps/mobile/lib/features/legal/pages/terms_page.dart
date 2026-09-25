import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

/// TERMS & CONDITIONS — plain-language terms for a Nigerian campus
/// marketplace, aligned with Google Play policy (Users > 13, no regulated
/// payments handled in-app), Apple App Store guidelines (clear disclosure,
/// no hidden subscriptions, privacy linkage) and Nigerian law (NDPA 2023,
/// FCCPA 2018, contract age of majority).
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      header: UsPageHeader(title: Text('TERMS & CONDITIONS')),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Meta(),
            SizedBox(height: 24),
            _Section(
              title: '1. Acceptance',
              body:
                  'By creating an account or using UniStash you agree to these '
                  'Terms. If you do not agree, do not use the app. You must '
                  'be at least 18 years old (or the age of legal majority in '
                  'Nigeria) to trade; accounts belonging to minors will be '
                  'suspended.',
            ),
            _Section(
              title: '2. What UniStash is',
              body:
                  'UniStash is a listing and communication service that '
                  'connects students of verified partner universities to buy, '
                  'sell and barter items on campus. We are not a party to '
                  'any transaction: we do not own, inspect, store, deliver '
                  'or warrant any item, and we do not handle or process '
                  'payments. Buyers pay sellers directly by cash or '
                  'transfer at their own agreed meetup.',
            ),
            _Section(
              title: '3. Your account',
              body:
                  'You must register with a valid school email from a '
                  'recognized partner university and keep your credentials '
                  'confidential. You are responsible for all activity under '
                  'your account. Impersonation, shared accounts, and '
                  'multiple accounts per person are not allowed.',
            ),
            _Section(
              title: '4. Your listings',
              body:
                  'You may only list items you own and are legally allowed '
                  'to sell. Listings must be truthful: real photos of the '
                  'actual item, accurate description of condition, defects '
                  'and price. The following are strictly prohibited:',
              bullets: [
                '''Counterfeit or pirated goods; items that infringe intellectual property''',
                '''Weapons, drugs (including prescription-only medicines), tobacco, alcohol and gambling''',
                '''Sexual content or services; live animals''',
                '''Exam malpractice materials, forged documents or academic dishonesty services''',
                '''Stolen property or "too good to be true" scam bait''',
                '''Anything illegal under Nigerian law, including the Cybercrimes Act 2015 and FCCPA 2018''',
              ],
            ),
            _Section(
              title: '5. Safety (read this)',
              body:
                  'UniStash meetings are between strangers. Inspect items '
                  'properly before paying, meet in public and well-lit '
                  'campus locations, never send money or a deposit before '
                  'seeing the item, and keep conversations inside the app '
                  'where they can be reviewed if reported. UniStash does '
                  'not verify items or screen every user; your judgement is '
                  'the main safety mechanism.',
            ),
            _Section(
              title: '6. Fees',
              body:
                  'UniStash is free to use. We do not charge listing fees, '
                  'success fees or subscriptions, and we never ask for card '
                  'or bank details. If any feature is ever monetized, we '
                  'will tell you clearly and get your consent first, in '
                  'line with Google Play and Apple App Store rules.',
            ),
            _Section(
              title: '7. Content you post',
              body:
                  'You keep ownership of what you post, but you grant '
                  'UniStash a limited licence to host, display and '
                  'distribute it within the app for the purpose of '
                  'operating the marketplace. Do not post content you do '
                  'not have the rights to, and do not scrape, spam or '
                  'harass other users.',
            ),
            _Section(
              title: '8. Reporting and moderation',
              body:
                  'Report listings or users that break these Terms using '
                  'the in-app report action. We may remove content, limit '
                  'features or suspend accounts that violate these Terms, '
                  'or where required by law enforcement under due process.',
            ),
            _Section(
              title: '9. Ending these Terms',
              body:
                  'You may delete your account at any time from Settings. '
                  'Your account enters a 30-day grace period, after which '
                  'it is permanently deleted. We may suspend or terminate '
                  'accounts for serious or repeated breaches. Sections that '
                  'by their nature should survive termination (liability, '
                  'indemnity, disputes) do so.',
            ),
            _Section(
              title: '10. Disclaimers and liability',
              body:
                  'The service is provided "as is" without warranties of '
                  'any kind. To the maximum extent permitted by Nigerian '
                  'law, UniStash is not liable for the quality, safety or '
                  'legality of items, the truth of listings, the conduct '
                  'of users, or any loss arising from transactions between '
                  'users. Nothing in these Terms limits liability that '
                  'cannot be limited under law.',
            ),
            _Section(
              title: '11. Changes and governing law',
              body:
                  'We may update these Terms; material changes will be '
                  'announced in the app and the date above will change. '
                  'Continued use after changes means acceptance. These '
                  'Terms are governed by the laws of the Federal Republic '
                  'of Nigeria, and disputes fall under the courts of '
                  'Nigeria.',
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
      'Questions about these Terms? Contact support@uni-stash.com.',
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}
