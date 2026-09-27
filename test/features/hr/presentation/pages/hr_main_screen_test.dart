import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tHRDelegate;

  setUpAll(() {
    tHRDelegate = Delegate(
      uid: 'hr123',
      firstName: 'Omar',
      middleName: 'M',
      lastName: 'HR',
      fullName: 'Omar HR',
      nationalityID: '29901010101234',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '+201012345678',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1995, 1, 1),
      organizationUID: 'org1',
      organizationName: 'El-Ezaby Pharmacies',
      companyUID: 'comp1',
      companyName: 'Pharma Group',
      status: DelegateStatus.active,
      delegatePublicId: 'hr_pub123',
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

  test('HRMainScreen constructor holds correct delegate reference', () {
    final screen = HRMainScreen(delegate: tHRDelegate);
    expect(screen.delegate, equals(tHRDelegate));
    expect(screen.delegate.role, equals(UserRole.hr));
    expect(screen.delegate.companyUID, equals('comp1'));
    expect(screen.delegate.companyName, equals('Pharma Group'));
  });
}
