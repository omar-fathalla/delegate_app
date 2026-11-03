import 'package:delegate_app/core/utils/google_maps_loader.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var available = false;

  setUp(() {
    available = false;
    googleMapsAvailabilityOverride = () => available;
  });
  tearDown(() => googleMapsAvailabilityOverride = null);

  Future<void> pumpGate(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GoogleMapsReadyGate(
              timeout: Duration(seconds: 1),
              child: Text('MAP'),
            ),
          ),
        ),
      );

  testWidgets('builds child immediately when available (mobile)',
      (tester) async {
    available = true;
    await pumpGate(tester);
    expect(find.text('MAP'), findsOneWidget);
  });

  testWidgets('loader, then child once SDK appears', (tester) async {
    await pumpGate(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    available = true;
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('MAP'), findsOneWidget);
  });

  testWidgets('timeout shows unavailable + retry, never builds map',
      (tester) async {
    await pumpGate(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('MAP'), findsNothing);
    expect(find.text('الخريطة غير متاحة'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    available = true;
    await tester.tap(find.byKey(const Key('maps_gate_retry')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('MAP'), findsOneWidget);
  });
}
