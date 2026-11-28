// TAS-366: shared fake payroll data (no real people) for the calculator and
// the «مرتبي» / HR screen parity tests.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

const kFakePayrollCompany = 'seed-fake-co';

Delegate fakePayrollDelegate({
  String uid = 'fake-d1',
  String fullName = 'أحمد سمير حسن',
  bool annualLeaveEnabled = true,
  int annualLeaveQuota = 2,
  UserRole role = UserRole.delegate,
  DelegatePosition position = DelegatePosition.promoter,
}) =>
    Delegate(
      uid: uid,
      firstName: fullName.split(' ').first,
      middleName: '',
      lastName: '',
      fullName: fullName,
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '01000000001',
      gender: DelegateGender.male,
      position: position,
      birthDate: DateTime(1995),
      organizationUID: 'o-fake',
      organizationName: 'سلسلة تجريبية',
      companyUID: kFakePayrollCompany,
      companyName: 'شركة ألفا التجريبية',
      status: DelegateStatus.active,
      delegatePublicId: '',
      allReceiptCodes: const [],
      createdAt: DateTime(2026),
      createdBy: 'test',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: role,
      isAnnualLeaveEnabled: annualLeaveEnabled,
      annualLeaveQuota: annualLeaveQuota,
    );

Timestamp ts(int y, int m, int d, [int h = 0, int min = 0]) =>
    Timestamp.fromDate(DateTime(y, m, d, h, min));

Map<String, dynamic> checkIn(String uid, DateTime at, {Map<String, dynamic> extra = const {}}) => {
      'delegateId': uid,
      'companyId': kFakePayrollCompany,
      'type': 'check_in',
      'timestamp': Timestamp.fromDate(at),
      ...extra,
    };

Map<String, dynamic> checkOut(String uid, DateTime at) => {
      'delegateId': uid,
      'companyId': kFakePayrollCompany,
      'type': 'check_out',
      'timestamp': Timestamp.fromDate(at),
    };

/// Three October 2026 days: 8h, 6h and 10h.
List<Map<String, dynamic>> octoberAttendance(String uid) => [
      checkIn(uid, DateTime(2026, 10, 5, 8)),
      checkOut(uid, DateTime(2026, 10, 5, 16)),
      checkIn(uid, DateTime(2026, 10, 6, 8)),
      checkOut(uid, DateTime(2026, 10, 6, 14)),
      checkIn(uid, DateTime(2026, 10, 7, 8)),
      checkOut(uid, DateTime(2026, 10, 7, 18)),
      // September: ignored for October.
      checkIn(uid, DateTime(2026, 9, 7, 8)),
      checkOut(uid, DateTime(2026, 9, 7, 16)),
    ];

/// Annual: 1 day used in March, 3 asked in October (quota 2 → 1 paid).
/// Sick: 2 days in October (unpaid). Late excuse: not a leave day.
List<Map<String, dynamic>> octoberLeaves(String uid) => [
      {'delegateUid': uid, 'companyUID': kFakePayrollCompany, 'status': 'approved', 'type': 'annual', 'daysCount': 1, 'startDate': ts(2026, 3, 10)},
      {'delegateUid': uid, 'companyUID': kFakePayrollCompany, 'status': 'approved', 'type': 'annual', 'daysCount': 3, 'startDate': ts(2026, 10, 12)},
      {'delegateUid': uid, 'companyUID': kFakePayrollCompany, 'status': 'approved', 'type': 'sick', 'daysCount': 2, 'startDate': ts(2026, 10, 20)},
      {'delegateUid': uid, 'companyUID': kFakePayrollCompany, 'status': 'approved', 'type': 'late', 'daysCount': 1, 'startDate': ts(2026, 10, 21)},
      {'delegateUid': uid, 'companyUID': kFakePayrollCompany, 'status': 'pending', 'type': 'sick', 'daysCount': 4, 'startDate': ts(2026, 10, 25)},
    ];

/// ISSUED 50 + legacy `approved` 30 in October = 80. Pending (100) and
/// September (70) are not deducted in October.
List<Map<String, dynamic>> octoberPenalties(String uid) => [
      {'targetDelegateId': uid, 'companyId': kFakePayrollCompany, 'status': 'ISSUED', 'fineAmount': 50, 'createdAt': ts(2026, 10, 3)},
      {'targetDelegateId': uid, 'companyId': kFakePayrollCompany, 'status': 'approved', 'fineAmount': 30, 'createdAt': ts(2026, 10, 18)},
      {'targetDelegateId': uid, 'companyId': kFakePayrollCompany, 'status': 'PENDING', 'fineAmount': 100, 'createdAt': ts(2026, 10, 19)},
      {'targetDelegateId': uid, 'companyId': kFakePayrollCompany, 'status': 'ISSUED', 'fineAmount': 70, 'createdAt': ts(2026, 9, 19)},
    ];
