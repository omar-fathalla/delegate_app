// TAS-190: the delegate attendance detail has its own web address,
// `/hr/<tab>/delegate/<id>`. Opening that address loads the delegate by id,
// only from the signed-in HR user's company; a missing id or another
// company's delegate shows an empty state. Fake data only.
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Delegate _hr({String org = 'seed-fake-org', String company = 'co-alpha'}) =>
    Delegate(
      uid: 'seed-fake-hr',
      firstName: 'مسؤول',
      middleName: '',
      lastName: 'تجريبي',
      fullName: 'مسؤول تجريبي',
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '01000000099',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1990),
      organizationUID: org,
      organizationName: 'سلسلة تجريبية',
      companyUID: company,
      companyName: 'شركة تجريبية',
      status: DelegateStatus.approved,
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
      role: UserRole.hr,
    );

Map<String, dynamic> _delegateDoc(String name, {String? company}) => {
  'firstName': name,
  'fullName': name,
  'phoneNumber': '01000000001',
  if (company != null) 'companyUID': company,
  'status': 'approved',
};

Future<FakeFirebaseFirestore> _store() async {
  final fs = FakeFirebaseFirestore();
  final directory = fs
      .collection('organizations')
      .doc('seed-fake-org')
      .collection('companies')
      .doc('co-alpha')
      .collection('delegates');
  await directory.doc('d-in-dir').set(_delegateDoc('مندوب الدليل'));
  await fs
      .collection('users')
      .doc('d-profile')
      .set(_delegateDoc('مندوب الملف', company: 'co-alpha'));
  await fs
      .collection('users')
      .doc('d-other')
      .set(_delegateDoc('مندوب شركة أخرى', company: 'co-beta'));
  return fs;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  tearDown(() {
    HRDelegateAttendanceDetailScreen.debugFirestore = null;
    WebRuntimePolicy.debugReset();
  });

  group('loadHrDelegateForDetailUrl', () {
    test('reads the company delegate directory first', () async {
      final fs = await _store();
      final d = await loadHrDelegateForDetailUrl(
        firestore: fs,
        delegateId: 'd-in-dir',
        hrDelegate: _hr(),
      );
      expect(d?.uid, 'd-in-dir');
      expect(d?.fullName, 'مندوب الدليل');
      expect(d?.companyUID, 'co-alpha');
    });

    test('falls back to a profile of the same company', () async {
      final fs = await _store();
      final d = await loadHrDelegateForDetailUrl(
        firestore: fs,
        delegateId: 'd-profile',
        hrDelegate: _hr(),
      );
      expect(d?.uid, 'd-profile');
    });

    test('another company, a missing id or no company: nothing', () async {
      final fs = await _store();
      for (final id in ['d-other', 'd-missing', '', '  ']) {
        expect(
          await loadHrDelegateForDetailUrl(
            firestore: fs,
            delegateId: id,
            hrDelegate: _hr(),
          ),
          isNull,
          reason: id,
        );
      }
      // The directory of another company is never read.
      expect(
        await loadHrDelegateForDetailUrl(
          firestore: fs,
          delegateId: 'd-in-dir',
          hrDelegate: _hr(company: 'co-beta'),
        ),
        isNull,
      );
      expect(
        await loadHrDelegateForDetailUrl(
          firestore: fs,
          delegateId: 'd-profile',
          hrDelegate: _hr(company: ''),
        ),
        isNull,
      );
    });
  });

  group('openHrDelegateAttendanceDetailById', () {
    Future<void> pumpOpener(WidgetTester t, String id) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          home: HrInnerPageHost(
            navigatorKey: key,
            parentTitle: 'الحضور والانصراف',
            child: Navigator(
              key: key,
              pages: [
                MaterialPage<void>(
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => openHrDelegateAttendanceDetailById(
                          context,
                          delegateId: id,
                          hrDelegate: _hr(),
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ],
              onDidRemovePage: (_) {},
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    for (final id in ['d-other', 'd-missing']) {
      testWidgets('$id: an empty state at the same address', (t) async {
        final fs = await _store();
        HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;
        await pumpOpener(t, id);

        expect(find.byType(HrEmptyState), findsOneWidget);
        expect(
          find.byKey(const ValueKey('hr_delegate_detail_missing')),
          findsOneWidget,
        );
        expect(find.byType(HRDelegateAttendanceDetailScreen), findsNothing);
        // Nothing about the other company's delegate is shown.
        expect(find.textContaining('شركة أخرى'), findsNothing);
        final route = ModalRoute.of(t.element(find.byType(HrEmptyState)))!;
        expect(hrInnerRouteUrl(route), hrDelegateDetailUrlPath(id));
        expect(
          find.text(kHrDelegateDetailMissingTitle),
          findsOneWidget,
          reason: 'the breadcrumb title',
        );
      });
    }

    testWidgets('a delegate of the company opens its detail page', (t) async {
      final fs = await _store();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;
      await pumpOpener(t, 'd-in-dir');

      expect(find.byType(HrEmptyState), findsNothing);
      final screen = find.byType(HRDelegateAttendanceDetailScreen);
      expect(screen, findsOneWidget);
      expect(
        t.widget<HRDelegateAttendanceDetailScreen>(screen).inShell,
        isTrue,
      );
      final route = ModalRoute.of(t.element(screen))!;
      expect(hrInnerRouteUrl(route), 'delegate/d-in-dir');
      // The URL carries the id; the name is only in the breadcrumb.
      expect(hrInnerRouteUrl(route), isNot(contains('مندوب')));
    });
  });
}
