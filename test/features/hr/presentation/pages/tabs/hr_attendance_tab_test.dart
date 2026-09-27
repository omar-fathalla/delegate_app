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
    });
  });
}
