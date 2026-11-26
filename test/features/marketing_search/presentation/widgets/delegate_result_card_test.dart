import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/delegate_result_card.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  Widget createWidgetUnderTest(Delegate delegate) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DelegateResultCard(delegate: delegate),
        ),
      ),
    );
  }

  testWidgets('renders delegate details correctly', (tester) async {
    await initializeDateFormatting('en', null);
    
    final delegate = Delegate(
      uid: 'user1',
      firstName: 'Test',
      middleName: '',
      lastName: 'Delegate',
      fullName: 'Test Delegate',
      nationalityID: '12345678901234',
      motherName: '',
      city: 'Cairo',
      phoneNumber: '01234567890',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org1',
      organizationName: 'Test Org',
      companyUID: 'comp1',
      companyName: 'Test Company',
      status: DelegateStatus.active,
      delegatePublicId: 'pub1',
      allReceiptCodes: const [],
      createdAt: DateTime(2023, 1, 1),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidgetUnderTest(delegate));

    expect(find.text('Test Delegate'), findsOneWidget);
    expect(find.text('01234567890'), findsOneWidget);
    expect(find.text('12345678901234'), findsOneWidget);
    // english localization returns Male, Promoter
    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Promoter'), findsOneWidget);
    expect(find.text('Cairo'), findsOneWidget);
    expect(find.text('Test Company'), findsOneWidget);
  });
}
