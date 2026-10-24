/// Phone and national-ID checks shared by the delegate login form.
///
/// Kept free of localization so unit tests can cover the rules directly.
/// Staff passwords that contain letters are accepted by [validateLoginSecret]
/// so admin and other role logins can still be submitted from the same form.
const _englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
const _arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
const _persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

String _swapDigits(String value) {
  var normalized = value;
  for (var i = 0; i < _englishDigits.length; i++) {
    normalized = normalized.replaceAll(_arabicDigits[i], _englishDigits[i]);
    normalized = normalized.replaceAll(_persianDigits[i], _englishDigits[i]);
  }
  return normalized;
}

/// Normalizes Egyptian mobile numbers to the local `01xxxxxxxxx` form.
String normalizeEgyptianPhone(String phone) {
  var normalized = _swapDigits(phone.trim()).replaceAll(RegExp(r'[^\d+]'), '');

  if (normalized.startsWith('+20')) {
    normalized = '0${normalized.substring(3)}';
  } else if (normalized.startsWith('+2')) {
    normalized = normalized.substring(2);
  } else if (normalized.startsWith('0020')) {
    normalized = '0${normalized.substring(4)}';
  } else if (normalized.startsWith('002')) {
    normalized = normalized.substring(3);
  }

  if (normalized.length == 10 && RegExp(r'^1[0125]').hasMatch(normalized)) {
    normalized = '0$normalized';
  }

  return normalized;
}

/// Variants stored on existing delegate documents for the same mobile number.
List<String> egyptianPhoneVariants(String normalizedPhone) {
  final variants = <String>{normalizedPhone};
  if (normalizedPhone.startsWith('0') && normalizedPhone.length == 11) {
    final withoutZero = normalizedPhone.substring(1);
    variants.add(withoutZero);
    variants.add('20$withoutZero');
    variants.add('+20$withoutZero');
    variants.add('0020$withoutZero');
    variants.add('+2$normalizedPhone');
    variants.add('002$normalizedPhone');
  }
  return variants.toList();
}

String normalizeNationalId(String value) {
  return _swapDigits(value.trim()).replaceAll(RegExp(r'[\s-]'), '');
}

String? validateLoginPhone(
  String? value, {
  required String emptyMessage,
  required String invalidMessage,
}) {
  if (value == null || value.trim().isEmpty) return emptyMessage;
  final normalized = normalizeEgyptianPhone(value);
  if (!RegExp(r'^01[0125]\d{8}$').hasMatch(normalized)) {
    return invalidMessage;
  }
  return null;
}

String? validateLoginSecret(
  String? value, {
  required String emptyMessage,
  required String invalidMessage,
}) {
  if (value == null || value.trim().isEmpty) return emptyMessage;
  final normalized = normalizeNationalId(value);
  if (normalized.isEmpty) return emptyMessage;
  final digitsOnly = RegExp(r'^\d+$').hasMatch(normalized);
  // Egyptian national IDs are 14 digits. A non-numeric value is a staff
  // password submitted from the same field and is checked server-side.
  if (digitsOnly && normalized.length != 14) return invalidMessage;
  if (!digitsOnly && normalized.length < 4) return invalidMessage;
  return null;
}
