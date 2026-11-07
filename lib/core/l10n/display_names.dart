import 'package:delegate_app/l10n/app_localizations.dart';

/// Maps a raw chain/organization name (data, any casing or script) to its
/// localized display name. Unknown names are returned trimmed, unchanged.
String localizeChainName(String raw, AppLocalizations? l10n) {
  final clean = raw.trim();
  if (l10n == null || clean.isEmpty) return clean;
  final lower = clean.toLowerCase();
  if (lower.contains('fathalla') ||
      clean.contains('فتح الله') ||
      clean.contains('فتح_الله')) {
    return l10n.chainFathallaMarket;
  }
  if (lower.contains('beit') || clean.contains('بيت الجملة')) {
    return l10n.chainBeitElGomla;
  }
  if (lower.contains('gomla') ||
      lower.contains('jomla') ||
      clean.contains('جملة') ||
      clean.contains('جمله')) {
    return l10n.chainGomlaMarket;
  }
  if (lower.contains('zahran') || clean.contains('زهران')) {
    return l10n.chainZahranMarket;
  }
  if (lower.contains('carrefour') || clean.contains('كارفور')) {
    return l10n.chainCarrefour;
  }
  return clean;
}

final _arabicChars = RegExp(r'[\u0600-\u06FF]');
final _latinChars = RegExp(r'[A-Za-z]');

/// Names are often stored bilingually ("مندوب تجريبي Test Delegate").
/// Returns the part written in the active script, or [fallback] if none.
String nameForLocale(
  String fullName,
  String fallback, {
  required bool isArabic,
}) {
  final words = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final match = isArabic ? _arabicChars : _latinChars;
  final picked = words.where((w) => match.hasMatch(w)).toList();
  if (picked.isEmpty) return fallback;
  return picked.join(' ');
}

String firstNameForLocale(
  String fullName,
  String fallback, {
  required bool isArabic,
}) {
  final n = nameForLocale(fullName, '', isArabic: isArabic);
  if (n.isEmpty) return fallback;
  return n.split(' ').first;
}
