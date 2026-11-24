// TAS-112 (user decision 2026-11-24): the user picks the country (Egypt by
// default, or the UAE) instead of typing its code, then types the number.
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';

enum PhoneCountry {
  egypt('+20'),
  uae('+971');

  const PhoneCountry(this.dialCode);
  final String dialCode;

  /// The country a stored / typed number belongs to (Egypt when unsure).
  static PhoneCountry of(String phone) {
    final n = normalizeEgyptianPhone(phone);
    return RegExp(r'^05\d{8}$').hasMatch(n) ? PhoneCountry.uae : PhoneCountry.egypt;
  }
}

/// The number as the rest of the app expects it (01xxxxxxxxx / 05xxxxxxxx),
/// from the picked [country] and what the user typed in the number field.
/// A typed international number (+… or 00…) wins over the picker.
String composePhone(PhoneCountry country, String typed) {
  final raw = typed.trim();
  if (raw.isEmpty) return '';
  final compact = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (compact.startsWith('+') || compact.startsWith('00')) {
    return normalizeEgyptianPhone(compact);
  }
  var digits = normalizeEgyptianPhone(compact).replaceAll(RegExp(r'\D'), '');
  switch (country) {
    case PhoneCountry.egypt:
      if (digits.startsWith('20') && digits.length == 12) digits = digits.substring(2);
      if (!digits.startsWith('0')) digits = '0$digits';
      return digits;
    case PhoneCountry.uae:
      if (digits.startsWith('971') && digits.length == 12) digits = digits.substring(3);
      if (digits.startsWith('0')) digits = digits.substring(1);
      return '0$digits';
  }
}

/// The local part to show in the number field for a stored number.
String localPart(String phone) {
  final n = normalizeEgyptianPhone(phone);
  return n.startsWith('0') ? n.substring(1) : n;
}
