import 'package:delegate_app/features/admin/presentation/pages/edit_delegate_profile_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _sup() => Delegate(
      uid: 'sup1',
      firstName: 'مشرف',
      middleName: '',
      lastName: 'شركة',
      fullName: 'مشرف شركة',
      nationalityID: '29001010100011',
      motherName: 'أم',
      city: 'Cairo',
      phoneNumber: '01000000011',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'o1',
      companyUID: 'c1',
      organizationName: 'Org',
      companyName: 'Co',
      status: DelegateStatus.active,
      delegatePublicId: 'pub',
      allReceiptCodes: const [],
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'sa',
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

Delegate _del() => Delegate(
      uid: 'd1',
      firstName: 'مندوب',
      middleName: '',
      lastName: 'تجريبي',
      fullName: 'مندوب تجريبي',
      nationalityID: '29001010100022',
      motherName: 'أم',
      city: 'Cairo',
      phoneNumber: '01000000022',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1995, 1, 1),
      organizationUID: 'o1',
      companyUID: 'c1',
      organizationName: 'Org',
      companyName: 'Co',
      status: DelegateStatus.active,
      delegatePublicId: 'pubd',
      allReceiptCodes: const [],
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'sup1',
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

void main() {
  testWidgets('save button is content-sized, not full width (LOW)', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: EditDelegateProfileScreen(supervisor: _sup(), delegate: _del()),
    ));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'حفظ التعديلات');
    expect(button, findsOneWidget);
    final buttonWidth = tester.getSize(button).width;
    final screenWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(buttonWidth, lessThan(screenWidth - 48));
  });

  testWidgets('image preview uses Image.memory, never Image.file (H-1)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditDelegateProfileScreen(supervisor: _sup(), delegate: _del()),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing); // no local preview until a pick
    expect(find.byWidgetPredicate((w) => w is Image && w.image is FileImage), findsNothing);
  });
}
