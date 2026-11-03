import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// I-3: task date headers must follow the app locale, not intl's default `en`.
void main() {
  testWidgets('DateFormat with Localizations locale renders Arabic months',
      (tester) async {
    String? out;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (context) {
        out = DateFormat.yMMMMd(Localizations.localeOf(context).languageCode)
            .format(DateTime(2026, 10, 25));
        return const SizedBox();
      }),
    ));
    expect(out, contains('أكتوبر'));
    expect(out, isNot(contains('October')));
  });
}
