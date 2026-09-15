import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A 6-digit one-time-code input styled as two groups of three slots
/// separated by a dot, matching the auth screens' design language.
///
/// Wraps shadcn's [ShadInputOTP] (raw widget, not the form-field variant) so
/// the emitted [onChanged] value is the plain digit string with no padding —
/// pages bind it straight to their view model.
class UsOtpInput extends StatelessWidget {
  const UsOtpInput({
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.initialValue,
    this.addSpacerIcon = false,
  });

  /// Called with the digits entered so far (e.g. `'123'`, then `'123456'`).
  final ValueChanged<String> onChanged;

  final bool enabled;

  /// Optional seed for the slots (used by tests and code recovery).
  final String? initialValue;

  /// Whether to add a spacer icon between the groups of slots.
  final bool addSpacerIcon;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadInputOTP(
      maxLength: 6,
      gap: 0,
      enabled: enabled,
      initialValue: initialValue,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) => onChanged(value.replaceAll(' ', '')),
      children: [
        const ShadInputOTPGroup(
          children: [
            ShadInputOTPSlot(),
            ShadInputOTPSlot(),
            ShadInputOTPSlot(),
          ],
        ),
        if (addSpacerIcon)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              LucideIcons.dot,
              size: 18,
              color: theme.colorScheme.border,
            ),
          ),
        const ShadInputOTPGroup(
          children: [
            ShadInputOTPSlot(),
            ShadInputOTPSlot(),
            ShadInputOTPSlot(),
          ],
        ),
      ],
    );
  }
}
