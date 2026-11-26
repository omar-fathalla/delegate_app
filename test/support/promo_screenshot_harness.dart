import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

bool _promoFontsLoaded = false;

/// Loads Cairo once per test file. Call it from `setUpAll` so the load (and
/// the engine's `fontsChange` message) happens before any widget tree exists:
/// since Flutter 3.50 a font change that lands during a test leaves a pending
/// frame callback and fails it ("An animation is still running..."). A flag,
/// not a cached Future, so a later call inside `testWidgets` (FakeAsync) never
/// awaits a future from another zone.
Future<void> loadPromoTestFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  if (_promoFontsLoaded) return;
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
  await cairo.load();
  _promoFontsLoaded = true;
}

Future<ThemeData> promoTestTheme() async {
  await loadPromoTestFonts();
  return AppTheme.lightTheme(const Color(0xFF6750A4));
}

Widget promoTestApp({
  required ThemeData theme,
  required Widget child,
  bool wrapScaffold = true,
}) {
  return MaterialApp(
    theme: theme,
    locale: const Locale('ar'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    debugShowCheckedModeBanner: false,
    home: wrapScaffold
        ? Scaffold(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            body: child,
          )
        : child,
  );
}
