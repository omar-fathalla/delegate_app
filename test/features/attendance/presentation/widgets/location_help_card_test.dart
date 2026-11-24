import 'package:delegate_app/features/attendance/presentation/widgets/location_help_card.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-283: help card shown when the delegate's location check fails.
void main() {
  late int locationOpened;
  late int appOpened;

  setUp(() {
    locationOpened = 0;
    appOpened = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    required LocationFailureKind kind,
    VoidCallback? onRetry,
    bool isAndroid = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationHelpCard(
              kind: kind,
              onRetry: onRetry,
              isAndroid: isAndroid,
              openLocationSettings: () async {
                locationOpened++;
                return true;
              },
              openAppSettings: () async {
                appOpened++;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('GPS failure shows location settings, steps and retry', (
    tester,
  ) async {
    var retried = 0;
    await pump(
      tester,
      kind: LocationFailureKind.noFix,
      onRetry: () => retried++,
    );

    expect(find.text('فتح إعدادات الموقع'), findsOneWidget);
    expect(find.text('فتح إعدادات التطبيق'), findsNothing);
    expect(find.text('إعادة فحص الموقع'), findsOneWidget);
    expect(find.textContaining('دقة الموقع من Google'), findsOneWidget);
    expect(find.textContaining('أثناء استخدام التطبيق'), findsOneWidget);
    expect(find.textContaining('بلا قيود'), findsOneWidget);
    expect(find.textContaining('النقطة الزرقا'), findsOneWidget);

    await tester.tap(find.text('فتح إعدادات الموقع'));
    await tester.tap(find.text('إعادة فحص الموقع'));
    await tester.pump();
    expect(locationOpened, 1);
    expect(appOpened, 0);
    expect(retried, 1);
  });

  for (final kind in [
    LocationFailureKind.permissionDenied,
    LocationFailureKind.permissionDeniedForever,
  ]) {
    testWidgets('$kind shows the app settings button', (tester) async {
      await pump(tester, kind: kind);

      expect(find.text('فتح إعدادات التطبيق'), findsOneWidget);
      expect(find.text('فتح إعدادات الموقع'), findsOneWidget);

      await tester.tap(find.text('فتح إعدادات التطبيق'));
      await tester.pump();
      expect(appOpened, 1);
      expect(locationOpened, 0);
    });
  }

  testWidgets('no retry callback hides the retry button', (tester) async {
    await pump(tester, kind: LocationFailureKind.serviceOff);

    expect(find.text('إعادة فحص الموقع'), findsNothing);
    expect(find.textContaining('وجرّب تاني'), findsOneWidget);
  });

  testWidgets('iOS hides the Android-only steps', (tester) async {
    await pump(tester, kind: LocationFailureKind.noFix, isAndroid: false);

    expect(find.textContaining('بلا قيود'), findsNothing);
    expect(find.textContaining('دقة الموقع من Google'), findsNothing);
    expect(find.textContaining('أثناء استخدام التطبيق'), findsOneWidget);
    expect(find.text('فتح إعدادات الموقع'), findsOneWidget);
  });
}
