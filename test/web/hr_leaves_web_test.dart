// HR «طلبات الإجازات» page (TAS-151), fake data only.
// Web: «تسجيل إجازة» is a toolbar FilledButton (no FAB) and the create
// dialog's dropdown menus stay inside the dialog. Mobile keeps the FAB.
import 'package:dartz/dartz.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _co = 'seed-fake-co';

Delegate _person(String uid, String fullName, {UserRole role = UserRole.delegate}) =>
    Delegate(
      uid: uid,
      firstName: fullName.split(' ').first,
      middleName: '',
      lastName: '',
      fullName: fullName,
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '01000000000',
      gender: DelegateGender.male,
      position: role == UserRole.hr
          ? DelegatePosition.supervisor
          : DelegatePosition.promoter,
      birthDate: DateTime(1995),
      organizationUID: 'o-fake',
      organizationName: 'سلسلة تجريبية',
      companyUID: _co,
      companyName: 'شركة تجريبية',
      status: DelegateStatus.active,
      delegatePublicId: '',
      allReceiptCodes: const [],
      createdAt: DateTime(2026),
      createdBy: 'test',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: role,
    );

final _hr = _person('seed-fake-hr', 'مشرف تجريبي', role: UserRole.hr);

class _FakeGetCompanyDelegates extends Fake implements GetCompanyDelegates {
  @override
  Future<Either<Failure, CompanyDelegatesResult>> call(
    GetCompanyDelegatesParams params,
  ) async =>
      Right(CompanyDelegatesResult(delegates: [
        for (var i = 0; i < 12; i++) _person('fake-d$i', 'مندوب تجريبي $i'),
      ]));
}

Future<void> _pump(WidgetTester t, {required bool web}) async {
  WebRuntimePolicy.debugIsWebOverride = web;
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final fs = FakeFirebaseFirestore();
  await fs.collection('leave_requests').doc('fake-l1').set({
    'companyUID': _co,
    'delegateName': 'مندوب تجريبي 0',
    'status': 'pending',
    'type': 'annual',
  });
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HRLeavesAndExcusesScreen(
          hrDelegate: _hr,
          showAppBar: false,
          firestore: fs,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Rect _dialogRect(WidgetTester t) => t.getRect(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first,
    );

void _expectInside(Rect inner, Rect outer, String what) {
  const eps = 0.5;
  expect(
    inner.left >= outer.left - eps &&
        inner.top >= outer.top - eps &&
        inner.right <= outer.right + eps &&
        inner.bottom <= outer.bottom + eps,
    isTrue,
    reason: '$what $inner is outside the dialog $outer',
  );
}

void main() {
  setUp(() {
    sl.allowReassignment = true;
    sl.registerFactory<GetCompanyDelegates>(() => _FakeGetCompanyDelegates());
    WebRuntimePolicy.debugReset();
  });

  tearDown(WebRuntimePolicy.debugReset);

  testWidgets('web: toolbar «تسجيل إجازة» button, no FAB', (t) async {
    await _pump(t, web: true);
    expect(find.byType(FloatingActionButton), findsNothing);
    final button = find.byKey(const ValueKey('hr_leaves_create_button'));
    expect(button, findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'تسجيل إجازة'), findsOneWidget);
    // The button sits in the toolbar row, level with the search field.
    final search = t.getRect(find.byType(TextField).first);
    expect((t.getRect(button).center.dy - search.center.dy).abs(), lessThan(2));
  });

  testWidgets('mobile: keeps the «تسجيل» FAB, no toolbar button', (t) async {
    await _pump(t, web: false);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('تسجيل'), findsOneWidget);
    expect(find.byKey(const ValueKey('hr_leaves_create_button')), findsNothing);
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    // Mobile dialog keeps the original dropdowns.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsNothing);
  });

  testWidgets('web dialog: M3 labels and dropdown menus stay inside', (t) async {
    await _pump(t, web: true);
    await t.tap(find.byKey(const ValueKey('hr_leaves_create_button')));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    // Labels use the M3 type scale, never below 12 on web.
    for (final label in ['المندوب:', 'نوع الطلب:', 'سبب الطلب:', 'من تاريخ', 'إلى تاريخ']) {
      final size = t.widget<Text>(find.text(label)).style?.fontSize ?? 0;
      expect(size, greaterThanOrEqualTo(12), reason: label);
    }

    final dialog = _dialogRect(t);
    for (final key in ['hr_leave_type_menu', 'hr_leave_delegate_menu']) {
      final field = find.byKey(ValueKey(key));
      _expectInside(t.getRect(field), dialog, '$key field');
      await t.tap(field);
      await t.pumpAndSettle();
      final item = find.byType(MenuItemButton).first;
      final panel = find
          .ancestor(of: item, matching: find.byType(SingleChildScrollView))
          .first;
      _expectInside(t.getRect(panel), dialog, '$key menu');
      expect(t.getRect(panel).height, lessThanOrEqualTo(kHrLeaveDialogMenuHeight + 0.5));
      // Close the menu before the next one.
      await t.tapAt(dialog.topLeft + const Offset(40, 30));
      await t.pumpAndSettle();
    }

    // Picking a type still updates the field.
    await t.tap(find.byKey(const ValueKey('hr_leave_type_menu')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(MenuItemButton, 'إجازة مرضية'));
    await t.pumpAndSettle();
    final input = t.widget<TextField>(find.descendant(
      of: find.byKey(const ValueKey('hr_leave_type_menu')),
      matching: find.byType(TextField),
    ));
    expect(input.controller?.text, 'إجازة مرضية');
  });
}
