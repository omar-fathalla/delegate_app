// I-9: attendance card rows must fit a 360px phone with no overflow and keep
// the call / WhatsApp / history actions on-screen.
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Delegate _d() => Delegate(
      uid: '1', firstName: 'x', middleName: '', lastName: '',
      fullName: 'رحمة السيد محمود عبد الرحمن', nationalityID: '',
      motherName: '', city: 'Cairo', phoneNumber: '01000000000',
      gender: DelegateGender.female, position: DelegatePosition.promoter,
      birthDate: DateTime(1990), organizationUID: 'o',
      organizationName: 'energizer', companyUID: 'c', companyName: 'c',
      status: DelegateStatus.active, delegatePublicId: 'X',
      allReceiptCodes: const [], createdAt: DateTime(2024), createdBy: 't',
      hasPendingUpdate: false, isDeductedFromCompany: false, isPrinted: false,
      isProfileComplete: true, numberOfDocuments: 0, paymentAmount: 0,
      version: 1, documents: const [], role: UserRole.delegate,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  for (final width in [360.0, 390.0, 414.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('card rows fit at $width ($brightness)', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final record = HRAttendanceRecord(
          delegate: _d(),
          branchName: 'فتح الله ماركت - فرع سموحة الكبير بجوار المحطة',
          checkInTime: DateTime(2026, 11, 3, 8, 55),
          checkOutTime: DateTime(2026, 11, 3, 20, 25),
          isAutoCheckOut: true,
          deviceInfo: 'Samsung Galaxy A54 5G • Android 14 • build 1.14.3',
        );
        var calls = 0;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                // ListView padding (16) + card padding (14)
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(children: [
                  HRAttendanceCardTimes(record: record),
                  HRAttendanceCardActions(
                    deviceInfo: record.deviceInfo,
                    phoneNumber: record.delegate.phoneNumber,
                    onCall: () => calls++,
                    onWhatsApp: () => calls++,
                    onHistory: () => calls++,
                  ),
                ]),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        for (final tip in ['اتصال بالمندوب', 'مراسلة عبر واتساب']) {
          final r = tester.getRect(find.byTooltip(tip));
          expect(r.left >= 0 && r.right <= width, isTrue, reason: '$tip $r');
          await tester.tap(find.byTooltip(tip));
        }
        final h = tester.getRect(find.text('السجل الشهري والتفصيلي'));
        expect(h.left >= 0 && h.right <= width, isTrue, reason: '$h');
        expect(calls, 2);
      });
    }
  }
}
