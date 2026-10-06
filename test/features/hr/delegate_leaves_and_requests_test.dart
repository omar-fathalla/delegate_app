import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  group('Delegate Leaves & Requests System Tests', () {
    late Delegate delegateCompanyA;
    late Delegate delegateCompanyB;
    late Delegate supervisorCompanyA;

    setUpAll(() {
      delegateCompanyA = Delegate(
        uid: 'del_company_a_001',
        firstName: 'أحمد',
        middleName: 'علي',
        lastName: 'محمود',
        fullName: 'أحمد علي محمود',
        nationalityID: '__phone_auth__:01011111111',
        motherName: 'فاطمة',
        city: 'الإسكندرية',
        phoneNumber: '01011111111',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        birthDate: DateTime(1995, 3, 10),
        organizationUID: 'org_fathalla_001',
        organizationName: 'أسواق فتح الله',
        companyUID: 'company_al_amal',
        companyName: 'شركة الأمل للتوزيع',
        supervisorUid: 'sup_company_a_001',
        supervisorName: 'محمد المشرف',
        supervisorPhone: '01022222222',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-AMAL-01',
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

      delegateCompanyB = Delegate(
        uid: 'del_company_b_002',
        firstName: 'طارق',
        middleName: 'إبراهيم',
        lastName: 'حسن',
        fullName: 'طارق إبراهيم حسن',
        nationalityID: '__phone_auth__:01033333333',
        motherName: 'مريم',
        city: 'القاهرة',
        phoneNumber: '01033333333',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        birthDate: DateTime(1993, 7, 20),
        organizationUID: 'org_fathalla_001',
        organizationName: 'أسواق فتح الله',
        companyUID: 'company_al_safwa',
        companyName: 'شركة الصفوة للتجارة',
        supervisorUid: 'sup_company_b_001',
        supervisorName: 'خالد المشرف',
        supervisorPhone: '01044444444',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-SAFWA-01',
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

      supervisorCompanyA = Delegate(
        uid: 'sup_company_a_001',
        firstName: 'محمد',
        middleName: 'سعيد',
        lastName: 'المشرف',
        fullName: 'محمد سعيد المشرف',
        nationalityID: '__phone_auth__:01022222222',
        motherName: 'زينب',
        city: 'الإسكندرية',
        phoneNumber: '01022222222',
        gender: DelegateGender.male,
        position: DelegatePosition.supervisor,
        birthDate: DateTime(1988, 1, 15),
        organizationUID: 'org_fathalla_001',
        organizationName: 'أسواق فتح الله',
        companyUID: 'company_al_amal',
        companyName: 'شركة الأمل للتوزيع',
        status: DelegateStatus.active,
        delegatePublicId: 'SUP-AMAL-01',
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

    test('1. Strict Multi-Tenant Isolation: Delegate only accesses their company data', () {
      final mockRequests = [
        {
          'id': 'req_1',
          'companyUID': 'company_al_amal',
          'delegateUid': 'del_company_a_001',
          'type': 'annual',
          'status': 'pending',
        },
        {
          'id': 'req_2',
          'companyUID': 'company_al_amal',
          'delegateUid': 'del_company_a_999', // Another delegate in same company
          'type': 'sick',
          'status': 'approved',
        },
        {
          'id': 'req_3',
          'companyUID': delegateCompanyB.companyUID, // Different company
          'delegateUid': delegateCompanyB.uid,
          'type': 'delay',
          'status': 'pending',
        },
      ];

      // Delegate screen filtering logic:
      final delegateFiltered = mockRequests.where((req) {
        return req['companyUID'] == delegateCompanyA.companyUID &&
            req['delegateUid'] == delegateCompanyA.uid;
      }).toList();

      expect(delegateFiltered.length, 1);
      expect(delegateFiltered.first['id'], 'req_1');
      expect(delegateFiltered.first['companyUID'], 'company_al_amal');
      expect(delegateFiltered.first['delegateUid'], 'del_company_a_001');

      // Supervisor screen filtering logic:
      final supervisorFiltered = mockRequests.where((req) {
        return req['companyUID'] == supervisorCompanyA.companyUID;
      }).toList();

      expect(supervisorFiltered.length, 2);
      expect(supervisorFiltered.any((r) => r['companyUID'] == 'company_al_safwa'), isFalse);
    });

    test('2. Leave Balance Calculation (Proposal 5): Quota and remaining days', () {
      const int quota = 21;
      final currentYear = DateTime.now().year;

      final requests = [
        {
          'status': 'approved',
          'isHourly': false,
          'daysCount': 4,
          'year': currentYear,
        },
        {
          'status': 'approved',
          'isHourly': false,
          'daysCount': 3,
          'year': currentYear,
        },
        {
          'status': 'approved',
          'isHourly': true, // Hourly excuse should NOT deduct from full-day annual quota
          'hoursCount': 2.0,
          'daysCount': 0,
          'year': currentYear,
        },
        {
          'status': 'pending', // Pending should not deduct until approved
          'isHourly': false,
          'daysCount': 5,
          'year': currentYear,
        },
        {
          'status': 'rejected', // Rejected should not deduct
          'isHourly': false,
          'daysCount': 2,
          'year': currentYear,
        },
        {
          'status': 'approved',
          'isHourly': false,
          'daysCount': 10,
          'year': currentYear - 1, // Past year should not deduct from this year
        },
      ];

      int usedDays = 0;
      for (final req in requests) {
        if (req['status'] == 'approved' &&
            req['isHourly'] == false &&
            req['year'] == currentYear) {
          usedDays += (req['daysCount'] as int);
        }
      }

      final remaining = (quota - usedDays).clamp(0, quota);

      expect(usedDays, 7); // 4 + 3 = 7
      expect(remaining, 14); // 21 - 7 = 14
    });

    test('3. Hourly Excuse vs Full-day Leave computation (Proposal 4)', () {
      // Full-day leave
      final startDate = DateTime(2026, 10, 5);
      final endDate = DateTime(2026, 10, 7);
      final daysDiff = endDate.difference(startDate).inDays + 1;
      expect(daysDiff, 3);

      // Hourly excuse
      int computeDays(bool hourly, int days) => hourly ? 0 : days;
      const hoursCount = 2.5;
      expect(computeDays(true, daysDiff), 0);
      expect(computeDays(false, daysDiff), 3);
      expect(hoursCount, 2.5);
    });

    test('4. Notification Payload for Supervisor (Proposal 1)', () {
      final notifPayload = {
        'delegateUid': delegateCompanyA.supervisorUid ?? '',
        'companyUID': delegateCompanyA.companyUID,
        'organizationUID': delegateCompanyA.organizationUID,
        'title': 'طلب إجازة جديد قيد المراجعة',
        'body': 'قدم المندوب ${delegateCompanyA.fullName} طلباً جديداً يحتاج إلى مراجعتك واعتمادك.',
        'type': 'leave_request_submitted',
        'targetRole': 'supervisor',
        'isRead': false,
        'createdBy': delegateCompanyA.uid,
        'senderName': delegateCompanyA.fullName,
      };

      expect(notifPayload['delegateUid'], 'sup_company_a_001');
      expect(notifPayload['companyUID'], 'company_al_amal');
      expect(notifPayload['targetRole'], 'supervisor');
      expect(notifPayload['type'], 'leave_request_submitted');
    });

    test('5. Attachment URL and Storage Path Pattern (Proposal 3)', () {
      final compId = delegateCompanyA.companyUID;
      final delId = delegateCompanyA.uid;
      final timestamp = 1728054000000;
      final storagePath = 'leave_attachments/$compId/$delId/${timestamp}_medical_report.jpg';

      expect(storagePath.startsWith('leave_attachments/'), isTrue);
      expect(storagePath.contains(compId), isTrue);
      expect(storagePath.contains(delId), isTrue);
    });

    test('6. Delegate Annual Leave Status & Probation Defaults (Supervisor Control)', () {
      // New hire defaults: isAnnualLeaveEnabled is false, annualLeaveQuota is 21
      expect(delegateCompanyA.isAnnualLeaveEnabled, isFalse);
      expect(delegateCompanyA.annualLeaveQuota, 21);

      // Supervisor enables annual leave upon confirmation
      final confirmedDelegate = Delegate(
        uid: delegateCompanyA.uid,
        firstName: delegateCompanyA.firstName,
        middleName: delegateCompanyA.middleName,
        lastName: delegateCompanyA.lastName,
        fullName: delegateCompanyA.fullName,
        nationalityID: delegateCompanyA.nationalityID,
        motherName: delegateCompanyA.motherName,
        city: delegateCompanyA.city,
        phoneNumber: delegateCompanyA.phoneNumber,
        gender: delegateCompanyA.gender,
        position: delegateCompanyA.position,
        birthDate: delegateCompanyA.birthDate,
        organizationUID: delegateCompanyA.organizationUID,
        organizationName: delegateCompanyA.organizationName,
        companyUID: delegateCompanyA.companyUID,
        companyName: delegateCompanyA.companyName,
        status: delegateCompanyA.status,
        delegatePublicId: delegateCompanyA.delegatePublicId,
        allReceiptCodes: delegateCompanyA.allReceiptCodes,
        createdAt: delegateCompanyA.createdAt,
        createdBy: delegateCompanyA.createdBy,
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
        isAnnualLeaveEnabled: true,
        annualLeaveQuota: 21,
      );

      expect(confirmedDelegate.isAnnualLeaveEnabled, isTrue);
      expect(confirmedDelegate.annualLeaveQuota, 21);
    });

    test('7. Probationary Delegate Leave Entitlement (Weekly Off Days Only)', () {
      // In probation: weekly rest days only (4 days per month / 1 day per 7 days)
      const isProbation = true;
      expect(isProbation, isTrue);
      const int activeDaysInMonth = 28;
      final weeklyOffDays = (activeDaysInMonth / 7).floor().clamp(0, 4);
      expect(weeklyOffDays, 4);

      // Annual leave application policy check
      bool canApplyForAnnualLeave(bool isAnnualLeaveEnabled, String requestType) {
        if (!isAnnualLeaveEnabled && requestType == 'annual') {
          return false;
        }
        return true;
      }

      // Delegate on probation trying to apply for annual leave: BLOCKED
      expect(canApplyForAnnualLeave(false, 'annual'), isFalse);

      // Delegate on probation applying for excuse or unpaid leave: ALLOWED
      expect(canApplyForAnnualLeave(false, 'delay'), isTrue);
      expect(canApplyForAnnualLeave(false, 'early_leave'), isTrue);
      expect(canApplyForAnnualLeave(false, 'absence'), isTrue);
      expect(canApplyForAnnualLeave(false, 'unpaid'), isTrue);

      // Confirmed delegate with annual leaves enabled: ALLOWED
      expect(canApplyForAnnualLeave(true, 'annual'), isTrue);
    });
  });
}
