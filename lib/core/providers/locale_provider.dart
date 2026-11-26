import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ChangeNotifier] that manages the app's current locale.
///
/// Persists the user's language preference to [SharedPreferences].
///
/// Default is Arabic. Users who only had the old forced-English default
/// (`app_locale_default_en_v1`) and never explicitly chose a language are
/// migrated to Arabic once via `app_locale_default_ar_v2`. An explicit choice
/// (toggle / [setLocale]) is stored in `app_locale_explicit` and is never
/// overridden.
class LocaleProvider extends ChangeNotifier {
  static const _kLocaleKey = 'app_locale';
  /// Legacy flag from when English was forced as the first-run default.
  static const _kDefaultEnAppliedKey = 'app_locale_default_en_v1';
  /// One-time migration to Arabic as the product default.
  static const _kDefaultArAppliedKey = 'app_locale_default_ar_v2';
  /// Set when the user picks a language via [toggleLocale] / [setLocale].
  static const _kLocaleExplicitKey = 'app_locale_explicit';

  Locale _locale = const Locale('ar');
  final SharedPreferences _prefs;

  LocaleProvider(this._prefs) {
    final explicit = _prefs.getBool(_kLocaleExplicitKey) ?? false;
    final savedLocale = _prefs.getString(_kLocaleKey);
    final arDefaultApplied = _prefs.getBool(_kDefaultArAppliedKey) ?? false;

    if (explicit && savedLocale != null && savedLocale.isNotEmpty) {
      _locale = Locale(savedLocale);
      return;
    }

    if (!arDefaultApplied) {
      // Fresh installs + anyone still on the old forced-English default
      // (never explicitly chosen) land on Arabic.
      _locale = const Locale('ar');
      _prefs.setString(_kLocaleKey, 'ar');
      _prefs.setBool(_kDefaultArAppliedKey, true);
      // Keep legacy key readable for debugging; do not clear explicit=false.
      return;
    }

    if (savedLocale != null && savedLocale.isNotEmpty) {
      _locale = Locale(savedLocale);
    } else {
      _locale = const Locale('ar');
      _prefs.setString(_kLocaleKey, 'ar');
    }
  }

  Locale get locale => _locale;

  /// Whether the current locale is Arabic.
  bool get isArabic => _locale.languageCode == 'ar';

  /// Toggle between Arabic and English.
  void toggleLocale() {
    _locale = isArabic ? const Locale('en') : const Locale('ar');
    _prefs.setString(_kLocaleKey, _locale.languageCode);
    _prefs.setBool(_kLocaleExplicitKey, true);
    notifyListeners();
  }

  /// Set a specific locale.
  void setLocale(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    _prefs.setString(_kLocaleKey, locale.languageCode);
    _prefs.setBool(_kLocaleExplicitKey, true);
    notifyListeners();
  }

  // Exposed for tests / diagnostics.
  @visibleForTesting
  static String get localeKey => _kLocaleKey;

  @visibleForTesting
  static String get defaultEnAppliedKey => _kDefaultEnAppliedKey;

  @visibleForTesting
  static String get defaultArAppliedKey => _kDefaultArAppliedKey;

  @visibleForTesting
  static String get localeExplicitKey => _kLocaleExplicitKey;
}
