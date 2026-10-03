import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tHrDelegate;

  setUpAll(() {
    tHrDelegate = Delegate(
      uid: 'hr_user_001',
      firstName: 'Ahmed',
      middleName: 'M',
      lastName: 'HR',
      fullName: 'أحمد محمود (مسؤول الموارد البشرية)',
      nationalityID: '29001010101999',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '01000000001',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org_test',
      organizationName: 'شركة النيل للتوزيع',
      companyUID: 'comp_test',
      companyName: 'النيل لمستحضرات التجميل',
      status: DelegateStatus.active,
      delegatePublicId: 'hr_pub_001',
      allReceiptCodes: const [],
      createdAt: DateTime(2024, 1, 1),
      createdBy: 'super_admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.hr,
    );
  });

  group('AttendanceAdjustmentRecord Model Tests', () {
    test('Calculates positive duration diff correctly', () {
      final record = AttendanceAdjustmentRecord(
        id: 'adj_001',
        companyUID: 'comp_test',
        organizationUID: 'org_test',
        delegateUID: 'del_100',
        delegateName: 'محمود عبد الرحيم',
        delegatePhone: '01122334455',
        delegateRole: 'delegate',
        branchName: 'فرع مدينة نصر',
        attendanceSessionId: 'sess_100',
        sessionDate: DateTime(2026, 9, 29),
        originalCheckInTime: DateTime(2026, 9, 29, 9, 0),
        newCheckInTime: DateTime(2026, 9, 29, 9, 0),
        wasCheckInModified: false,
        originalCheckOutTime: null,
        newCheckOutTime: DateTime(2026, 9, 29, 17, 30),
        wasCheckOutModified: true,
        isNewCheckOutCreated: true,
        originalDurationMinutes: 0,
        newDurationMinutes: 510, // 8h 30m
        adjustedByUID: 'hr_user_001',
        adjustedByName: 'أحمد محمود',
        adjustedByRole: 'HR',
        reason: 'نسيان تسجيل الانصراف من قِبل المندوب',
        notes: 'تم التحقق من كاميرات الفرع',
        adjustedAt: DateTime(2026, 9, 30, 10, 0),
      );

      expect(record.durationDiffMinutes, equals(510));
      expect(record.formattedDurationDiff, equals('+8 س و 30 د'));
      expect(record.wasCheckInModified, isFalse);
      expect(record.wasCheckOutModified, isTrue);
      expect(record.isNewCheckOutCreated, isTrue);
    });

    test('Calculates negative duration diff correctly', () {
      final record = AttendanceAdjustmentRecord(
        id: 'adj_002',
        companyUID: 'comp_test',
        organizationUID: 'org_test',
        delegateUID: 'del_101',
        delegateName: 'سارة إبراهيم',
        delegatePhone: '01234567890',
        delegateRole: 'delegate',
        branchName: 'فرع المعادي',
        attendanceSessionId: 'sess_101',
        sessionDate: DateTime(2026, 9, 28),
        originalCheckInTime: DateTime(2026, 9, 28, 9, 0),
        newCheckInTime: DateTime(2026, 9, 28, 9, 45), // Late arrival corrected
        wasCheckInModified: true,
        originalCheckOutTime: DateTime(2026, 9, 28, 17, 0),
        newCheckOutTime: DateTime(2026, 9, 28, 17, 0),
        wasCheckOutModified: false,
        isNewCheckOutCreated: false,
        originalDurationMinutes: 480, // 8h
        newDurationMinutes: 435, // 7h 15m (-45m)
        adjustedByUID: 'hr_user_001',
        adjustedByName: 'أحمد محمود',
        adjustedByRole: 'HR',
        reason: 'تصحيح توقيت الحضور (حضور مبكر/متأخر معتمد)',
        adjustedAt: DateTime(2026, 9, 29, 11, 0),
      );

      expect(record.durationDiffMinutes, equals(-45));
      expect(record.formattedDurationDiff, equals('-45 دقيقة'));
      expect(record.wasCheckInModified, isTrue);
      expect(record.wasCheckOutModified, isFalse);
    });

    test('Handles zero duration diff correctly', () {
      final record = AttendanceAdjustmentRecord(
        id: 'adj_003',
        companyUID: 'comp_test',
        organizationUID: 'org_test',
        delegateUID: 'del_102',
        delegateName: 'خالد يوسف',
        delegatePhone: '01011223344',
        delegateRole: 'supervisor',
        branchName: 'فرع الدقي',
        attendanceSessionId: 'sess_102',
        sessionDate: DateTime(2026, 9, 27),
        originalCheckInTime: DateTime(2026, 9, 27, 8, 30),
        newCheckInTime: DateTime(2026, 9, 27, 9, 0),
        wasCheckInModified: true,
        originalCheckOutTime: DateTime(2026, 9, 27, 16, 30),
        newCheckOutTime: DateTime(2026, 9, 27, 17, 0),
        wasCheckOutModified: true,
        isNewCheckOutCreated: false,
        originalDurationMinutes: 480,
        newDurationMinutes: 480,
        adjustedByUID: 'hr_user_001',
        adjustedByName: 'أحمد محمود',
        adjustedByRole: 'HR',
        reason: 'توجيه إداري بتمديد أو تعديل فترة العمل',
        adjustedAt: DateTime(2026, 9, 28, 9, 0),
      );

      expect(record.durationDiffMinutes, equals(0));
      expect(record.formattedDurationDiff, equals('بدون تغيير'));
    });
  });

  group('DelegateAttendanceSession Manual Adjustment Metadata Tests', () {
    test('Session preserves manual adjustment flags and audit metadata', () {
      final checkIn = DateTime(2026, 9, 27, 9, 0);
      final checkOut = DateTime(2026, 9, 27, 17, 30);
      final adjustedAt = DateTime(2026, 9, 28, 14, 20);

      final session = DelegateAttendanceSession(
        id: 'sess_adj_1',
        checkInTime: checkIn,
        checkOutTime: checkOut,
        branchName: 'فرع سموحة',
        checkOutDocId: 'checkout_doc_99',
        isManuallyAdjusted: true,
        lastAdjustedBy: 'أحمد محمود (HR)',
        lastAdjustedAt: adjustedAt,
        adjustmentReason: 'نسيان تسجيل الانصراف من قِبل المندوب',
      );

      expect(session.isManuallyAdjusted, isTrue);
      expect(session.lastAdjustedBy, equals('أحمد محمود (HR)'));
      expect(session.lastAdjustedAt, equals(adjustedAt));
      expect(session.adjustmentReason, equals('نسيان تسجيل الانصراف من قِبل المندوب'));
      expect(session.checkOutDocId, equals('checkout_doc_99'));
      expect(session.duration, equals(const Duration(hours: 8, minutes: 30)));
    });
  });

  group('HRAttendanceAdjustmentsScreen Widget Tests', () {
    test('Constructor accepts valid hrDelegate and parameters', () {
      final screen = HRAttendanceAdjustmentsScreen(
        hrDelegate: tHrDelegate,
        showAppBar: false,
        initialDelegateUID: 'del_100',
      );

      expect(screen.hrDelegate, equals(tHrDelegate));
      expect(screen.showAppBar, isFalse);
      expect(screen.initialDelegateUID, equals('del_100'));
      expect(screen.hrDelegate.companyUID, equals('comp_test'));
    });
  });
}
