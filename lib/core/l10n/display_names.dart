import 'package:delegate_app/l10n/app_localizations.dart';

/// Known retail chains. TAS-214: «بيت الجملة» contains the word «جملة», so it
/// must be matched before Gomla Market; every chain-name helper goes through
/// [chainKeyOf] so the order lives in one place.
enum ChainKey { fathalla, beitElGomla, gomla, zahran, carrefour, other }

ChainKey chainKeyOf(String raw) {
  final clean = raw.trim();
  final lower = clean.toLowerCase();
  if (lower.contains('fathalla') ||
      clean.contains('فتح الله') ||
      clean.contains('فتح_الله')) {
    return ChainKey.fathalla;
  }
  if (lower.contains('beit') ||
      clean.contains('بيت الجملة') ||
      clean.contains('بيت الجمله')) {
    return ChainKey.beitElGomla;
  }
  if (lower.contains('gomla') ||
      lower.contains('jomla') ||
      clean.contains('جملة') ||
      clean.contains('جمله')) {
    return ChainKey.gomla;
  }
  if (lower.contains('zahran') || clean.contains('زهران')) {
    return ChainKey.zahran;
  }
  if (lower.contains('carrefour') || clean.contains('كارفور')) {
    return ChainKey.carrefour;
  }
  return ChainKey.other;
}

/// Fixed Arabic/English display name for a raw chain name (no l10n needed).
/// Unknown names are returned trimmed, unchanged.
String chainDisplayName(String raw, {bool isArabic = true}) {
  switch (chainKeyOf(raw)) {
    case ChainKey.fathalla:
      return isArabic ? 'فتح الله ماركت' : 'Fathalla Market';
    case ChainKey.beitElGomla:
      return isArabic ? 'بيت الجملة' : 'Beit El Gomla';
    case ChainKey.gomla:
      return isArabic ? 'جملة ماركت' : 'Gomla Market';
    case ChainKey.zahran:
      return isArabic ? 'زهران ماركت' : 'Zahran Market';
    case ChainKey.carrefour:
      return isArabic ? 'كارفور' : 'Carrefour';
    case ChainKey.other:
      return raw.trim();
  }
}

/// Maps a raw chain/organization name (data, any casing or script) to its
/// localized display name. Unknown names are returned trimmed, unchanged.
String localizeChainName(String raw, AppLocalizations? l10n) {
  final clean = raw.trim();
  if (l10n == null || clean.isEmpty) return clean;
  switch (chainKeyOf(clean)) {
    case ChainKey.fathalla:
      return l10n.chainFathallaMarket;
    case ChainKey.beitElGomla:
      return l10n.chainBeitElGomla;
    case ChainKey.gomla:
      return l10n.chainGomlaMarket;
    case ChainKey.zahran:
      return l10n.chainZahranMarket;
    case ChainKey.carrefour:
      return l10n.chainCarrefour;
    case ChainKey.other:
      return clean;
  }
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
  final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  // Compound Arabic first names: «عبد الرحمن», «أبو بكر», not «عبد».
  const prefixes = {'عبد', 'عبدال', 'أبو', 'ابو', 'أبي'};
  if (parts.length > 1 && prefixes.contains(parts.first)) {
    return '${parts[0]} ${parts[1]}';
  }
  return parts.first;
}
