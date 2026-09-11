import 'package:flutter/services.dart';

/// [TextInputFormatter] that masks input as Naira currency.
///
/// Digits only, grouped in thousands with commas and prefixed with `₦`
/// (e.g. typing `15000` produces `₦15,000`).
class NairaCurrencyInputFormatter extends TextInputFormatter {
  NairaCurrencyInputFormatter();

  static final RegExp _nonDigits = RegExp('[^0-9]');

  /// Maximum number of digits accepted (₦999,999,999,999).
  static const int maxDigits = 12;

  /// Parses formatted text back into an amount.
  ///
  /// Returns null when the text contains no digits.
  static double? parse(String text) {
    final digits = text.replaceAll(_nonDigits, '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_nonDigits, '');
    if (digits.isEmpty) return TextEditingValue.empty;

    var amount = digits;
    while (amount.length > 1 && amount.startsWith('0')) {
      amount = amount.substring(1);
    }
    if (amount.length > maxDigits) {
      amount = amount.substring(0, maxDigits);
    }

    final formatted = '₦${_groupThousands(amount)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buffer.write(',');
    }
    return buffer.toString();
  }
}
