import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleProvider Arabic default', () {
    test('fresh install defaults to Arabic', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = LocaleProvider(prefs);

      expect(provider.locale, const Locale('ar'));
      expect(provider.isArabic, isTrue);
      expect(prefs.getString(LocaleProvider.localeKey), 'ar');
      expect(prefs.getBool(LocaleProvider.defaultArAppliedKey), isTrue);
      expect(prefs.getBool(LocaleProvider.localeExplicitKey), isNull);
    });

    test('migrates forced English default to Arabic when never explicit', () async {
      SharedPreferences.setMockInitialValues({
        LocaleProvider.localeKey: 'en',
        LocaleProvider.defaultEnAppliedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = LocaleProvider(prefs);

      expect(provider.locale, const Locale('ar'));
      expect(prefs.getString(LocaleProvider.localeKey), 'ar');
      expect(prefs.getBool(LocaleProvider.defaultArAppliedKey), isTrue);
    });

    test('keeps explicit English choice', () async {
      SharedPreferences.setMockInitialValues({
        LocaleProvider.localeKey: 'en',
        LocaleProvider.localeExplicitKey: true,
        LocaleProvider.defaultArAppliedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = LocaleProvider(prefs);

      expect(provider.locale, const Locale('en'));
      expect(provider.isArabic, isFalse);
    });

    test('toggleLocale persists explicit English then Arabic', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = LocaleProvider(prefs);

      expect(provider.isArabic, isTrue);
      provider.toggleLocale();
      expect(provider.locale, const Locale('en'));
      expect(prefs.getBool(LocaleProvider.localeExplicitKey), isTrue);

      provider.toggleLocale();
      expect(provider.locale, const Locale('ar'));
      expect(prefs.getBool(LocaleProvider.localeExplicitKey), isTrue);
    });

    test('setLocale marks preference as explicit', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = LocaleProvider(prefs);

      provider.setLocale(const Locale('en'));
      expect(provider.locale, const Locale('en'));
      expect(prefs.getBool(LocaleProvider.localeExplicitKey), isTrue);
    });
  });
}
