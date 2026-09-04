import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class ResetPasswordPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return UsPage(
      header: const UsPageHeader(),
      body: SingleChildScrollView(
        padding: const .only(top: 16),
        child: AuthPageShell(
          title: Align(
            alignment: .centerLeft,
            child: Text('RESET PASSWORD', style: theme.textTheme.h1),
          ),
          description: RichText(
            text: TextSpan(
              children: [
                const TextSpan(
                  text: "We've sent a 6-digit one-time passcode to ",
                ),
                TextSpan(
                  text: 'david.michael@stu.cu.edu.ng',
                  style: theme.textTheme.muted.copyWith(
                    color: theme.colorScheme.foreground,
                    fontWeight: .bold,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
              style: theme.textTheme.muted.copyWith(
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          body: ShadForm(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                ShadInputOTPFormField(
                  onChanged: (v) => print('OTP: $v'),
                  label: const Text('OTP'),
                  description: const Text('Expires in 06:20'),
                  maxLength: 6,
                  gap: 0,
                  children: const [
                    ShadInputOTPGroup(
                      children: [
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                      ],
                    ),
                    Spacer(),
                    Icon(LucideIcons.dot),
                    Spacer(),
                    ShadInputOTPGroup(
                      children: [
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ShadButton(
                  onPressed: () {},
                  child: Text('CONTINUE'),
                ),
                const SizedBox(height: 8),
                ShadButton.ghost(
                  onPressed: () {},
                  child: const Text('Resend Code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
