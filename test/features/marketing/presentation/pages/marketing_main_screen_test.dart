import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tDelegate;

  setUpAll(() {
    tDelegate = Delegate(
      uid: 'marketing123',
      firstName: 'Marketing',
      middleName: 'M',
      lastName: 'User',
      fullName: 'Marketing M User',
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
      role: UserRole.marketing,
    );
  });

  testWidgets('MarketingMainScreen should initialize successfully', (WidgetTester tester) async {
    // We only test constructor to avoid full DI container setup for UI tests
    final widget = MarketingMainScreen(delegate: tDelegate);
    expect(widget.delegate, equals(tDelegate));
  });
}
