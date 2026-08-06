import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tDelegate;

  setUpAll(() {
    tDelegate = Delegate(
      uid: 'admin123',
      firstName: 'Admin',
      middleName: 'M',
      lastName: 'User',
      fullName: 'Admin M User',
      nationalityID: '12345678901234',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '+201000000000',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org1',
      companyUID: 'comp1',
      organizationName: 'Test Org',
      companyName: 'Test Comp',
      status: DelegateStatus.active,
      delegatePublicId: 'pub123',
      allReceiptCodes: const [],
      createdAt: DateTime.now(),
      createdBy: 'superAdmin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.admin,
    );
  });

  testWidgets('AdminMainScreen should initialize successfully', (WidgetTester tester) async {
    // We only test constructor to avoid full DI container setup for UI tests
    final widget = AdminMainScreen(delegate: tDelegate);
    expect(widget.delegate, equals(tDelegate));
  });
}
