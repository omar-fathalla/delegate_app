import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/company_result_card.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  Widget createWidgetUnderTest(Company company) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompanyResultCard(company: company),
        ),
      ),
    );
  }

  testWidgets('renders company details correctly', (tester) async {
    await initializeDateFormatting('en', null);
    
    final company = Company(
      uid: 'comp1',
      name: 'Test Company',
      companyCodeInOrg: '1234',
      organizationUID: 'org1',
      type: 'Retail',
      status: 'active',
      createdAt: DateTime(2023, 1, 1),
      updatedAt: DateTime(2023, 1, 1),
      admins: 1,
      delegates: 5,
      deferredPayment: true,
      phone: '1234567890',
      email: 'test@company.com',
      code: 123,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidgetUnderTest(company));

    expect(find.text('Test Company'), findsOneWidget);
    expect(find.text('الكود: 1234'), findsOneWidget);
    expect(find.text('Retail'), findsOneWidget);
    // Active translates to 'نشط' if arabic but default uses english without localizations set up here.
    // We are just using default locale (en) in test unless specified
    expect(find.text('active'), findsOneWidget);
    expect(find.text('5 مندوب'), findsOneWidget);
    expect(find.text('دفع مؤجل'), findsOneWidget);
    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('test@company.com'), findsOneWidget);
  });
}
