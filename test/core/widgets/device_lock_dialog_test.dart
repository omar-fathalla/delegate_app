import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';

void main() {
  testWidgets('tells the delegate the device-change request was already sent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceLockDialog(requestAlreadyFiled: true),
      ),
    );
    await tester.pump();

    expect(find.text('تنبيه أمان: الحساب مقترن بجهاز آخر'), findsOneWidget);
    expect(find.text('طلب فك الارتباط قيد المراجعة'), findsOneWidget);
    expect(find.text('إرسال طلب لفك الارتباط'), findsNothing);
  });
}
