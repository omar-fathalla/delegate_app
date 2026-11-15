import 'package:delegate_app/core/security/delegate_status_policy.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _delegate({DelegateStatus status = DelegateStatus.active}) => Delegate(
      uid: 'd1',
      firstName: 'a',
      middleName: 'b',
      lastName: 'c',
      fullName: 'a b c',
      nationalityID: '1',
      motherName: 'm',
      city: 'cairo',
      phoneNumber: '010',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990),
      organizationUID: 'o1',
      organizationName: 'O',
      companyUID: 'c1',
      companyName: 'C',
      status: status,
      delegatePublicId: 'p',
      allReceiptCodes: const [],
      createdAt: DateTime(2020),
      createdBy: 'x',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.delegate,
      allOrganizationNames: const [],
    );

void main() {
  group('shouldSupervisorMarkDelegatePendingOnDocReplace', () {
    test('active delegate, supervisor viewer without approver path', () {
      expect(
        shouldSupervisorMarkDelegatePendingOnDocReplace(
          target: _delegate(),
          viewerRole: UserRole.admin,
          viewerUid: 'sup',
          viewerCompanyUID: 'c1',
          viewerIsDocApprover: false,
        ),
        isTrue,
      );
    });
    test('deny company admin approver path', () {
      expect(
        shouldSupervisorMarkDelegatePendingOnDocReplace(
          target: _delegate(),
          viewerRole: UserRole.admin,
          viewerUid: 'ca',
          viewerCompanyUID: 'c1',
          viewerIsDocApprover: true,
        ),
        isFalse,
      );
    });
  });

  group('canClientLiftSuspendedDelegateStatus', () {
    test('only super-admin and technical support', () {
      expect(canClientLiftSuspendedDelegateStatus(UserRole.superAdmin), isTrue);
      expect(canClientLiftSuspendedDelegateStatus(UserRole.technicalSupport), isTrue);
      expect(canClientLiftSuspendedDelegateStatus(UserRole.admin), isFalse);
      expect(canClientLiftSuspendedDelegateStatus(UserRole.organizationAdmin), isFalse);
    });
  });

  group('canCancelUnpaidNewDelegateRequest', () {
    test('deny when paymentStatus PAID', () {
      expect(
        canCancelUnpaidNewDelegateRequest(
          requestType: 'new_delegate',
          paymentStatus: 'PAID',
          callerUid: 'sup',
          createdBy: 'admin1',
          supervisorUid: 'sup',
          callerFirestoreRole: 'supervisor',
          callerCompanyUID: 'c1',
          requestCompanyUID: 'c1',
          callerMappedRole: UserRole.admin,
        ),
        isFalse,
      );
    });
    test('supervisor same company may cancel', () {
      expect(
        canCancelUnpaidNewDelegateRequest(
          requestType: 'new_delegate',
          paymentStatus: 'pending',
          callerUid: 'sup',
          createdBy: 'other',
          supervisorUid: 'other',
          callerFirestoreRole: 'supervisor',
          callerCompanyUID: 'c1',
          requestCompanyUID: 'c1',
          callerMappedRole: UserRole.admin,
        ),
        isTrue,
      );
    });
    test('deny HR', () {
      expect(
        canCancelUnpaidNewDelegateRequest(
          requestType: 'new_delegate',
          paymentStatus: 'pending',
          callerUid: 'hr1',
          createdBy: 'other',
          supervisorUid: 'sup',
          callerFirestoreRole: 'hr',
          callerCompanyUID: 'c1',
          requestCompanyUID: 'c1',
          callerMappedRole: UserRole.hr,
        ),
        isFalse,
      );
    });
    test('renewal unchanged for HR', () {
      expect(
        canCancelUnpaidNewDelegateRequest(
          requestType: 'renewal',
          paymentStatus: 'pending',
          callerUid: 'hr1',
          createdBy: 'other',
          supervisorUid: 'sup',
          callerFirestoreRole: 'hr',
          callerCompanyUID: 'c1',
          requestCompanyUID: 'c1',
          callerMappedRole: UserRole.hr,
        ),
        isTrue,
      );
    });
  });
}