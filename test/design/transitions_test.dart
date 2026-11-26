import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_localizations.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/features/playground/sections/transitions.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TashilTheme.light(),
        locale: TashilLocale.arabic,
        supportedLocales: TashilLocale.supported,
        localizationsDelegates: TashilLocale.delegates,
        home: const Scaffold(body: TransitionsSection()),
      ),
    );
    await _settle(tester);
  }

  testWidgets('forward/backward flow walks cart, payment, receipt (RTL)', (
    tester,
  ) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('افتح السلة'), 300);
    await tester.ensureVisible(find.text('افتح السلة'));
    await _settle(tester);
    await tester.tap(find.text('افتح السلة'));
    await _settle(tester);
    expect(find.text('خطوة 1 من 3'), findsOneWidget);
    await tester.tap(find.text('التالي: الدفع'));
    await _settle(tester);
    await tester.tap(find.text('التالي: الإيصال'));
    await _settle(tester);
    expect(find.text('خطوة 3 من 3'), findsOneWidget);
    await tester.tap(find.text('إنهاء'));
    await _settle(tester);
    expect(find.text('افتح السلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('container transform opens product details', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('زيت عباد الشمس'), 300);
    await tester.ensureVisible(find.text('زيت عباد الشمس'));
    await _settle(tester);
    await tester.tap(find.text('زيت عباد الشمس'));
    await _settle(tester);
    expect(find.byType(CloseButton), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await _settle(tester);
    expect(find.byType(CloseButton), findsNothing);
  });

  testWidgets('skeleton loader shows then reveals content', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('مزامنة الأصناف'), 300);
    await tester.ensureVisible(find.text('مزامنة الأصناف'));
    await _settle(tester);
    await tester.tap(find.text('مزامنة الأصناف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('أرز مصري 5 كجم'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('أرز مصري 5 كجم'), findsOneWidget);
  });
}
