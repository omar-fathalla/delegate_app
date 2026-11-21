import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tDelegate;

  setUpAll(() {
    tDelegate = Delegate(
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
      organizationName: 'El-Ezaby Pharmacies',
      companyUID: 'comp1',
      companyName: 'Pharma Group',
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
  });

  group('HRAttendanceRecord presence status classification', () {
    test('should classify as isPresent when checked in but not checked out', () {
      final record = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 8, 30),
        checkOutTime: null,
        branchName: 'فرع المعادي',
        isInsideGeofence: true,
      );

      expect(record.isPresent, isTrue);
      expect(record.isDeparted, isFalse);
      expect(record.isAbsent, isFalse);
    });

    test('should classify as isDeparted when both checked in and checked out', () {
      final record = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 8, 30),
        checkOutTime: DateTime(2026, 9, 27, 16, 45),
        branchName: 'فرع المعادي',
        isInsideGeofence: true,
      );

      expect(record.isPresent, isFalse);
      expect(record.isDeparted, isTrue);
      expect(record.isAbsent, isFalse);
    });

    test('should classify as isAbsent when check-in time is null', () {
      final record = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: null,
        checkOutTime: null,
      );

      expect(record.isPresent, isFalse);
      expect(record.isDeparted, isFalse);
      expect(record.isAbsent, isTrue);
      expect(record.safetyLevel, equals('unknown'));
      expect(record.integrityStatus, equals('none'));
    });
  });

  group('Anti-Fraud & Integrity Score (مؤشر النزاهة الرقمية ومكافحة الاحتيال)', () {
    test('🟢 100% Trusted: distance <= 50m, no fraud alerts, no VPN', () {
      final record = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 9, 0),
        branchName: 'فرع المعادي',
        distanceMeters: 23.5,
        isInsideGeofence: true,
        isMockLocation: false,
        isVpnUsed: false,
        hasSecurityViolation: false,
        trustScore: 100,
        integrityStatus: 'trusted',
      );

      expect(record.trustScore, equals(100));
      expect(record.integrityStatus, equals('trusted'));
      expect(record.safetyLevel, equals('safe'));
      expect(record.isMockLocation, isFalse);
      expect(record.isVpnUsed, isFalse);
      expect(record.hasSecurityViolation, isFalse);
    });

    test('🟡 Warning (Suspicious): distance > 50m or VPN used', () {
      final recordWarningDistance = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 9, 0),
        branchName: 'فرع مدينة نصر',
        distanceMeters: 145.0,
        isInsideGeofence: false,
        isMockLocation: false,
        isVpnUsed: false,
        trustScore: 75,
        integrityStatus: 'warning',
        violationReason: 'تسجيل خارج نطاق الفرع (145م)',
      );

      expect(recordWarningDistance.trustScore, equals(75));
      expect(recordWarningDistance.integrityStatus, equals('warning'));
      expect(recordWarningDistance.safetyLevel, equals('warning'));

      final recordVpn = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 9, 0),
        branchName: 'فرع المعادي',
        distanceMeters: 20.0,
        isInsideGeofence: true,
        isMockLocation: false,
        isVpnUsed: true,
        trustScore: 55,
        integrityStatus: 'warning',
        violationReason: 'رصد اتصال مشبوه عبر VPN/Proxy',
      );

      expect(recordVpn.trustScore, equals(55));
      expect(recordVpn.integrityStatus, equals('warning'));
      expect(recordVpn.isVpnUsed, isTrue);
    });

    test('🔴 Critical Violation: Fake GPS / Mock Location detected', () {
      final recordMock = HRAttendanceRecord(
        delegate: tDelegate,
        checkInTime: DateTime(2026, 9, 27, 9, 0),
        branchName: 'فرع الدقي',
        distanceMeters: 10.0,
        isInsideGeofence: true,
        isMockLocation: true,
        hasSecurityViolation: true,
        trustScore: 15,
        integrityStatus: 'violation',
        violationReason: 'رصد تزييف موقع (Mock Location / Fake GPS)',
      );

      expect(recordMock.trustScore, equals(15));
      expect(recordMock.integrityStatus, equals('violation'));
      expect(recordMock.safetyLevel, equals('violation'));
      expect(recordMock.hasSecurityViolation, isTrue);
      expect(recordMock.isMockLocation, isTrue);
    });
  });

  group('Cards grid column count (TAS-147)', () {
    test('every column is at least the card min width', () {
      for (final w in [400.0, 718.0, 760.0, 1000.0, 1208.0, 1600.0, 2400.0]) {
        final cols = hrAttendanceCardColumns(w);
        final cell = (w - (cols - 1) * kHrAttendanceCardsGridSpacing) / cols;
        expect(cols, inInclusiveRange(1, kHrAttendanceCardsMaxColumns));
        if (cols > 1) {
          expect(cell, greaterThanOrEqualTo(kHrAttendanceCardMinWidth),
              reason: 'width $w -> $cols columns of $cell');
        }
      }
    });

    test('column count follows the width', () {
      // Grid starts at 750 => 718 inside the 16px padding.
      expect(hrAttendanceCardColumns(718), 1);
      expect(hrAttendanceCardColumns(732), 2);
      expect(hrAttendanceCardColumns(1104), 3);
      expect(hrAttendanceCardColumns(1476), 4);
      expect(hrAttendanceCardColumns(3000), kHrAttendanceCardsMaxColumns);
      expect(hrAttendanceCardColumns(0), 1);
    });
  });

  test('view toggle uses the agreed names «جدول» / «بطاقات»', () {
    for (final path in [
      'lib/features/hr/presentation/pages/tabs/hr_attendance_tab.dart',
      'lib/features/hr/presentation/pages/tabs/hr_delegates_tab.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains("label: 'كروت'"), isFalse, reason: path);
      expect(src.contains("label: 'بطاقات'"), isTrue, reason: path);
      expect(src.contains("label: 'جدول'"), isTrue, reason: path);
    }
  });
}
