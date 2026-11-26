// Attendance table on the shared HR table widgets (TAS-115).
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

Delegate _delegate() => Delegate(
      uid: 'del1',
      firstName: 'Ahmed',
      middleName: 'Ali',
      lastName: 'Hassan',
      fullName: 'Ahmed Ali Hassan',
      nationalityID: '29501010101234',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '01012345678',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1995, 1, 1),
      organizationUID: 'org1',
      organizationName: 'Org',
      companyUID: 'comp1',
      companyName: 'Company',
      status: DelegateStatus.active,
      delegatePublicId: 'del_pub1',
      allReceiptCodes: const [],
      createdAt: DateTime(2024, 1, 1),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.delegate,
    );

void main() {
  final d = _delegate();

  group('status chip mapping', () {
    test('present is success', () {
      final s = hrAttendanceStatus(
        HRAttendanceRecord(delegate: d, checkInTime: DateTime(2026, 9, 27, 9)),
      );
      expect(s.tone, HrStatusTone.success);
      expect(s.label, 'حاضر الآن');
      expect(s.icon, Icons.check_circle_rounded);
    });

    // Approved 21 Nov 2026 (TAS-174): a normal check-out and a leave are
    // calm (info, blue); only an auto check-out is a warning.
    test('departed is info', () {
      final s = hrAttendanceStatus(
        HRAttendanceRecord(
          delegate: d,
          checkInTime: DateTime(2026, 9, 27, 9),
          checkOutTime: DateTime(2026, 9, 27, 17),
        ),
      );
      expect(s.tone, HrStatusTone.info);
      expect(s.label, 'انصرف اليوم');
    });

    test('auto check-out stays a warning', () {
      final s = hrAttendanceStatus(
        HRAttendanceRecord(
          delegate: d,
          checkInTime: DateTime(2026, 9, 27, 9),
          isAutoCheckOut: true,
        ),
      );
      expect(s.tone, HrStatusTone.warning);
      expect(s.label, 'انصرف (تلقائي)');
    });

    test('approved leave is info', () {
      final s = hrAttendanceStatus(
        HRAttendanceRecord(delegate: d, isOnApprovedLeave: true),
      );
      expect(s.tone, HrStatusTone.info);
    });

    test('no check-in is neutral «لم يسجل»', () {
      final s = hrAttendanceStatus(HRAttendanceRecord(delegate: d));
      expect(s.tone, HrStatusTone.neutral);
      expect(s.label, 'لم يسجل');
      expect(s.icon, Icons.schedule_rounded);
    });
  });

  testWidgets('header keeps all six columns at 56px', (tester) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: HrTableHeader(
              columns: hrAttendanceTableColumns,
              keyPrefix: 'hr_attendance_header_',
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HrTableHeader)).height, 56);
    for (final title in [
      'المندوب',
      'الحالة',
      'الفرع',
      'الحضور • الانصراف • الساعات',
      'النطاق الجغرافي',
      'الإجراءات',
    ]) {
      expect(find.byKey(Key('hr_attendance_header_$title')), findsOneWidget);
    }
  });

  test('table mode is built on the shared table widgets', () {
    final src = File(
      'lib/features/hr/presentation/pages/tabs/hr_attendance_tab.dart',
    ).readAsStringSync();
    final start = src.indexOf('Widget _buildTableView(');
    final end = src.indexOf('Widget _buildKpiCard(', start);
    final table = src.substring(start, end);
    expect(table, contains('HrTableCard('));
    expect(table, contains('HrTableHeader('));
    expect(table, contains('HrTableDivider()'));

    final rowStart = src.indexOf(
      'class _HRAttendanceTableRowItemState',
    );
    final rowEnd = src.indexOf('Widget _buildTimeHoursGroup(', rowStart);
    final row = src.substring(rowStart, rowEnd);
    expect(row, contains('HrTableRow('));
    expect(row, contains('HrStatusChip('));
    expect(row, isNot(contains('Color(0x')), reason: 'no raw hex colors');
  });
}
