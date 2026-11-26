import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-384: in the delegate header the organization is information only.
/// A tap on it must not open the profile (the name and role still do), it is
/// a label and not a chip, and the header has no avatar any more.
void main() {
  final delegate = Delegate(
    uid: 'seed-fake-d',
    firstName: 'مندوب',
    middleName: '',
    lastName: 'تجريبي',
    fullName: 'مندوب تجريبي',
    nationalityID: '',
    motherName: '',
    city: '',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    paymentAmount: 0,
    birthDate: DateTime(1990),
    organizationUID: 'org',
    organizationName: 'Fake Org',
    companyUID: 'co',
    companyName: 'Fake Co',
    status: DelegateStatus.active,
    delegatePublicId: '',
    allReceiptCodes: const [],
    createdAt: DateTime(2026),
    createdBy: 'seed',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    version: 1,
    documents: const [],
    role: UserRole.delegate,
  );

  Future<GoRouter> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: UniversalAppHeader(
              delegate: delegate,
              menuItems: const [],
              onMenuSelected: (_) {},
              useDrawer: true,
              firestore: FakeFirebaseFirestore(),
            ),
            drawer: const Drawer(),
          ),
        ),
        GoRoute(
          path: '/user-profile',
          builder: (_, _) => const Scaffold(body: Text('PROFILE')),
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        routerConfig: router,
      ),
    );
    await t.pumpAndSettle();
    return router;
  }

  testWidgets('a tap on the organization does not open the profile', (
    t,
  ) async {
    await pump(t);
    expect(find.byType(ActiveOrganizationLabel), findsOneWidget);
    await t.tap(find.text('Fake Org'));
    await t.pumpAndSettle();
    expect(find.text('PROFILE'), findsNothing);
  });

  testWidgets('a tap on the name still opens the profile', (t) async {
    await pump(t);
    await t.tap(find.text('مندوب تجريبي'));
    await t.pumpAndSettle();
    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('no avatar and no chip in the delegate header', (t) async {
    await pump(t);
    expect(find.byType(AppAvatar), findsNothing);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });
}
