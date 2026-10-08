import 'package:delegate_app/features/admin/presentation/pages/super_admin_hr_system_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Delegate tSuperAdmin;

  setUpAll(() {
    tSuperAdmin = Delegate(
      uid: 'superadmin123',
      firstName: 'Omar',
      middleName: 'M',
      lastName: 'Fathalla',
      fullName: 'Omar Fathalla',
      nationalityID: '12345678901234',
      motherName: 'Mother',
      city: 'Alexandria',
      phoneNumber: '+201000000000',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org1',
      companyUID: '',
      organizationName: 'Test Org',
      companyName: '',
      status: DelegateStatus.active,
      delegatePublicId: 'pub123',
      allReceiptCodes: const [],
      createdAt: DateTime.now(),
      createdBy: 'system',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.superAdmin,
    );
  });

  testWidgets('SuperAdminHRSystemScreen renders all 5 HR modules and header banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SuperAdminHRSystemScreen(delegate: tSuperAdmin),
        ),
      ),
    );

    // Verify AppBar and Header
    expect(find.text('HR System'), findsWidgets);
    expect(find.text('نظام الموارد البشرية وإدارة شؤون الموظفين'), findsOneWidget);

    // Verify 5 HR modules
    expect(find.text('سجل الحضور والانصراف'), findsOneWidget);
    expect(find.text('Live Tracking'), findsOneWidget);
    expect(find.text('طلبات الإجازات والأعذار'), findsOneWidget);
    expect(find.text('مسير الرواتب والعمولات'), findsOneWidget);
    expect(find.text('سجل تعديلات الحضور والانصراف'), findsOneWidget);
  });
}
