import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' as intl;
import 'package:material_ui/material_ui.dart';

/// Arabic-first locale setup shared by the app and the playground.
///
/// `ar` makes the whole tree RTL and gives Arabic labels to built-in M3
/// widgets (date picker, time picker, text selection menu, …).
abstract final class TashilLocale {
  static const arabic = Locale('ar', 'EG');
  static const supported = [arabic, Locale('en')];

  /// Material (with Western digits) + Cupertino + Widgets localizations.
  ///
  /// [WesternDigitsMaterialLocalizations.delegate] comes first so it wins
  /// over the stock Material delegate for the same type.
  static const delegates = <LocalizationsDelegate<dynamic>>[
    WesternDigitsMaterialLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ];
}

/// Google's own Material translations (same strings, same widgets), but
/// with dates and numbers in Western digits (0-9), the Tashil rule.
///
/// The stock `ar_EG` translations format the date and time pickers with
/// Arabic-Indic digits (٢٦ نوفمبر). This delegate loads the official
/// translation and only swaps the intl formatters it is built with.
abstract final class WesternDigitsMaterialLocalizations {
  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _Delegate();
}

class _Delegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _Delegate();

  static const _stock = GlobalMaterialLocalizations.delegate;

  @override
  bool isSupported(Locale locale) => _stock.isSupported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      // The stock load also loads intl's date symbols for the locale.
      _stock.load(locale).then((_) {
        final name = intl.Intl.canonicalizedLocale(locale.toString());
        final dateLocale = intl.DateFormat.localeExists(name)
            ? name
            : locale.languageCode;
        intl.DateFormat d(intl.DateFormat Function(String) make) =>
            make(dateLocale)..useNativeDigits = false;
        return SynchronousFuture<MaterialLocalizations>(
          getMaterialTranslation(
            locale,
            d(intl.DateFormat.y),
            d(intl.DateFormat.yMd),
            d(intl.DateFormat.yMMMd),
            d(intl.DateFormat.MMMEd),
            d(intl.DateFormat.yMMMMEEEEd),
            d(intl.DateFormat.yMMMM),
            d(intl.DateFormat.MMMd),
            intl.NumberFormat.decimalPattern('en'),
            intl.NumberFormat('00', 'en'),
          )!,
        );
      });

  @override
  bool shouldReload(_Delegate old) => false;
}
