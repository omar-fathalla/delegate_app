import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ChangeNotifier] that manages the app's current locale.
///
/// Persists the user's language preference to [SharedPreferences].
class LocaleProvider extends ChangeNotifier {
  static const _kLocaleKey = 'app_locale';
  static const _kDefaultEnAppliedKey = 'app_locale_default_en_v1';

  Locale _locale = const Locale('en');
  final SharedPreferences _prefs;

  LocaleProvider(this._prefs) {
    final defaultEnApplied = _prefs.getBool(_kDefaultEnAppliedKey) ?? false;
    if (!defaultEnApplied) {
      _locale = const Locale('en');
      _prefs.setString(_kLocaleKey, 'en');
      _prefs.setBool(_kDefaultEnAppliedKey, true);
    } else {
      final savedLocale = _prefs.getString(_kLocaleKey);
      if (savedLocale != null) {
        _locale = Locale(savedLocale);
      }
    }
  }

  Locale get locale => _locale;

  /// Whether the current locale is Arabic.
  bool get isArabic => _locale.languageCode == 'ar';

  /// Toggle between Arabic and English.
  void toggleLocale() {
    _locale = isArabic ? const Locale('en') : const Locale('ar');
    _prefs.setString(_kLocaleKey, _locale.languageCode);
    notifyListeners();
  }

  /// Set a specific locale.
  void setLocale(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    _prefs.setString(_kLocaleKey, locale.languageCode);
    notifyListeners();
  }
}
