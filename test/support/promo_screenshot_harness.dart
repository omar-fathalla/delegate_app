import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> loadPromoTestFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
  await cairo.load();
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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    debugShowCheckedModeBanner: false,
    home: wrapScaffold
        ? Scaffold(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            body: child,
          )
        : child,
  );
}
