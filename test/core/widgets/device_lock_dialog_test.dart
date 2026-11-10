import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

Widget _app({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('ar'),
      Locale('en'),
    ],
    locale: const Locale('ar'),
    home: home,
  );
}

void main() {
  testWidgets('pending unbind is a mandatory button and the dialog cannot be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => DeviceLockDialog.show(
                  context,
                  requestAlreadyFiled: true,
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('تنبيه أمان: الحساب مقترن بجهاز آخر'), findsOneWidget);
    expect(find.text('طلب فك ارتباط قيد المراجعة'), findsOneWidget);
    expect(find.text('إرسال طلب لفك الارتباط'), findsNothing);
    expect(find.text('إغلاق'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);

    // System/back pop must not close the dialog.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تنبيه أمان: الحساب مقترن بجهاز آخر'), findsOneWidget);

    await tester.tap(find.text('طلب فك ارتباط قيد المراجعة'));
    await tester.pumpAndSettle();

    expect(find.text('تنبيه أمان: الحساب مقترن بجهاز آخر'), findsNothing);
    expect(find.text('تم إرسال الطلب إلى المشرف'), findsOneWidget);
  });

  testWidgets('tells the delegate the device-change request was already sent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(home: const DeviceLockDialog(requestAlreadyFiled: true)),
    );
    await tester.pump();

    expect(find.text('تنبيه أمان: الحساب مقترن بجهاز آخر'), findsOneWidget);
    expect(find.text('طلب فك ارتباط قيد المراجعة'), findsOneWidget);
    expect(find.text('إرسال طلب لفك الارتباط'), findsNothing);
    expect(find.text('إغلاق'), findsNothing);
  });
}
