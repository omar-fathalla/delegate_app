// TAS-273: a forced logout applies only to sessions that started before it.
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _delegate() => Delegate(
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
      status: DelegateStatus.active,
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
  final reset = DateTime(2026, 11, 23, 12);

  test('session start is the last sign-in, not the oldest createdAt', () {
    final d = _delegate(); // createdAt 2020
    expect(SessionManagementService.sessionStartedAt(d, authLastSignIn: DateTime(2026, 11, 24)), DateTime(2026, 11, 24));
    expect(SessionManagementService.sessionStartedAt(d), d.createdAt);
  });

  test('a reset logs out a session that started before it', () {
    expect(SessionManagementService.forceLogoutApplies(reset, DateTime(2026, 11, 23, 9)), isTrue);
  });

  test('after signing in again the same reset no longer applies', () {
    expect(SessionManagementService.forceLogoutApplies(reset, DateTime(2026, 11, 23, 13)), isFalse);
  });

  test('no reset stamp, no logout', () {
    expect(SessionManagementService.forceLogoutApplies(null, DateTime(2020)), isFalse);
  });
}
