// TAS-397: «الفرع مكانه غلط؟». Typed geofence refusal, the delegate's
// report (branch picked by the delegate, nearest only a suggestion), the
// snackbar action in both refusal paths, and the reviewer screen by role.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_server_api.dart';
import 'package:delegate_app/features/branch_reports/data/branch_location_report_repository.dart';
import 'package:delegate_app/features/branch_reports/domain/branch_location_report.dart';
import 'package:delegate_app/features/branch_reports/presentation/branch_location_reports_screen.dart';
import 'package:delegate_app/features/branch_reports/presentation/report_branch_location_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

const _org = 'seed-fake-tas397-org';
const _co = 'seed-fake-tas397-co';

Delegate _person(
  String uid, {
  UserRole role = UserRole.delegate,
  String company = _co,
  DelegatePosition position = DelegatePosition.promoter,
}) => Delegate(
  uid: uid,
  firstName: 'تجربة',
  middleName: '',
  lastName: uid,
  fullName: 'تجربة $uid',
  nationalityID: '__phone_auth__:0100000$uid',
  motherName: '',
  city: 'القاهرة',
  phoneNumber: '0100000$uid',
  gender: DelegateGender.male,
  position: position,
  birthDate: DateTime(1995),
  organizationUID: _org,
  organizationName: 'سلسلة تجريبية',
  companyUID: company,
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: 'DEL-$uid',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'seed',
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

// Branch A is stored 4.2 km away (its position is wrong, as in TAS-343);
// branch B is stored close to the delegate, but it is not where they stand.
const _branchA = Branch(
  id: 'br-a',
  branchName: 'فرع أ',
  latitude: 30.0800,
  longitude: 31.2357,
  geofenceRadius: 100,
  organizationUID: _org,
);
const _branchB = Branch(
  id: 'br-b',
  branchName: 'فرع ب',
  latitude: 30.0446,
  longitude: 31.2360,
  geofenceRadius: 100,
  organizationUID: _org,
);
const _at = ReportPosition(lat: 30.0444, lng: 31.2357, accuracy: 12);

Widget _app(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  group('GeofenceOutsideFailure', () {
    test('is still a ServerFailure with the same message', () {
      const f = GeofenceOutsideFailure('أنت خارج نطاق الفرع (300 متر).');
      expect(f, isA<ServerFailure>());
      expect(f.message, 'أنت خارج نطاق الفرع (300 متر).');
    });

    test('the server refusal outside_branch maps to it; others do not', () {
      final e = attendanceServerError('failed-precondition', {
        'reason': 'outside_branch',
        'message': 'إنت برّه نطاق الفرع (420 متر). المسموح 150 متر.',
        'distanceMeters': 420,
        'allowedMeters': 150,
      }, null);
      expect(e, isA<GeofenceOutsideFailure>());
      final g = e as GeofenceOutsideFailure;
      expect(g.distanceMeters, 420);
      expect(g.allowedMeters, 150);
      expect(g.message, contains('420'));

      final other = attendanceServerError('failed-precondition', {
        'reason': 'same_branch_today',
        'message': 'سجّلت حضور هنا النهارده.',
      }, null);
      expect(other, isA<ServerFailure>());
      expect(other, isNot(isA<GeofenceOutsideFailure>()));
    });
  });

  group('report model', () {
    test(
      'id is {delegateId}_{branchId}; only the delegate fields, status open',
      () {
        final r = buildBranchReport(
          delegate: _person('d1'),
          branch: _branchA,
          at: _at,
          note: '  أنا جوه الفرع  ',
        );
        expect(r.id, 'd1_br-a');
        final f = r.toFields();
        expect(f['status'], 'open');
        expect(f['companyUID'], _co);
        expect(f['organizationUID'], _org);
        expect(f['note'], 'أنا جوه الفرع');
        expect(f['distanceMeters'], greaterThan(3500));
        expect(
          f.keys.toSet().difference({
            'delegateId',
            'delegateName',
            'companyUID',
            'organizationUID',
            'branchId',
            'branchName',
            'branchLat',
            'branchLng',
            'branchRadius',
            'lat',
            'lng',
            'accuracy',
            'isMocked',
            'distanceMeters',
            'note',
            'status',
          }),
          isEmpty,
        );
      },
    );

    test('the suggestion is listed first, then by distance', () {
      final ordered = orderBranchesForReport(
        [_branchA, _branchB],
        _at,
        suggestedBranchId: 'br-a',
      );
      expect(ordered.map((b) => b.id), ['br-a', 'br-b']);
      expect(
        orderBranchesForReport([_branchA, _branchB], _at).map((b) => b.id),
        ['br-b', 'br-a'],
      );
    });

    test('reviewers by role: company supervisor yes, HR and delegates no', () {
      expect(
        BranchReportViewer.of(_person('s', role: UserRole.admin)),
        BranchReportViewer.companySupervisor,
      );
      expect(
        BranchReportViewer.of(_person('o', role: UserRole.organizationAdmin)),
        BranchReportViewer.chainAdmin,
      );
      expect(
        BranchReportViewer.of(_person('a', role: UserRole.superAdmin)),
        BranchReportViewer.globalStaff,
      );
      expect(
        BranchReportViewer.of(_person('h', role: UserRole.hr)),
        BranchReportViewer.none,
      );
      expect(
        BranchReportViewer.of(
          _person('ds', position: DelegatePosition.supervisor),
        ),
        BranchReportViewer.none,
        reason: 'a delegate with position supervisor reviews nothing',
      );
    });
  });

  group('the delegate picks the branch', () {
    testWidgets('nearest is only a suggestion; the chosen branch is sent', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _app(
          ReportBranchLocationSheet(
            delegate: _person('d1'),
            branches: const [_branchA, _branchB],
            at: _at,
            suggestedBranchId: 'br-b',
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      expect(find.textContaining(BranchReportTexts.nearest), findsOneWidget);

      // Nothing chosen yet: no report.
      await tester.tap(find.byKey(const ValueKey('branch_report_send')));
      await tester.pump();
      expect(find.text(BranchReportTexts.chooseBranch), findsOneWidget);
      expect(
        (await db.collection(kBranchLocationReportsCollection).get()).size,
        0,
      );

      // The delegate stands in A (stored far away), not the suggested B.
      await tester.tap(find.byKey(const ValueKey('branch_report_option_br-a')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('branch_report_send')));
      await tester.pumpAndSettle();

      final doc = await db
          .collection(kBranchLocationReportsCollection)
          .doc('d1_br-a')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.get('branchId'), 'br-a');
      expect(doc.get('status'), 'open');
      // The branch itself is untouched (no branch write anywhere).
      expect((await db.collection('branches').get()).size, 0);
    });
  });

  group('«الفرع مكانه غلط؟» on the refusal snackbar', () {
    testWidgets('with a report target the action shows and opens it', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showGeofenceRefusalSnackBar(
                c,
                'أنت خارج نطاق الفرع (4200 متر).',
                onReport: () => opened++,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      // Let the snackbar finish sliding in before tapping its action.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(BranchReportTexts.action), findsOneWidget);
      await tester.tap(find.text(BranchReportTexts.action));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('without one (staff, view only) the plain message stays', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  showGeofenceRefusalSnackBar(c, 'أنت خارج نطاق الفرع.'),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('أنت خارج نطاق الفرع.'), findsOneWidget);
      expect(find.text(BranchReportTexts.action), findsNothing);
    });

    test('both refusal paths of the attendance screen use it', () {
      final src = File(
        'lib/features/attendance/presentation/pages/attendance_screen.dart',
      ).readAsStringSync();
      // The screen's own geofence block and the bloc's AttendanceError.
      expect(
        RegExp(r'_showOutsideGeofence\(parentContext, message\)').hasMatch(src),
        isTrue,
      );
      expect(
        RegExp(
          r'state\.outsideGeofence[\s\S]{0,80}_showOutsideGeofence',
        ).hasMatch(src),
        isTrue,
      );
      expect(src, contains('showGeofenceRefusalSnackBar('));
    });
  });

  group('reviewer screen', () {
    Future<FakeFirebaseFirestore> seeded(String status) async {
      final db = FakeFirebaseFirestore();
      await db.collection(kBranchLocationReportsCollection).doc('d1_br-a').set({
        ...buildBranchReport(
          delegate: _person('d1'),
          branch: _branchA,
          at: _at,
        ).toFields(),
        'status': status,
        'createdAt': DateTime(2026, 11, 28, 9),
      });
      return db;
    }

    testWidgets('company supervisor forwards an open report', (tester) async {
      final db = await seeded('open');
      final sup = _person('sup', role: UserRole.admin);
      await tester.pumpWidget(
        _app(
          BranchLocationReportsScreen(
            viewer: sup,
            showAppBar: false,
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('فرع أ'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('branch_report_forward_d1_br-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(BranchReportsScreenTexts.forward).last);
      await tester.pumpAndSettle();
      final doc = await db
          .collection(kBranchLocationReportsCollection)
          .doc('d1_br-a')
          .get();
      expect(doc.get('status'), 'forwarded');
      expect(doc.get('reviewedBy'), 'sup');
    });

    testWidgets('rejecting needs a reason', (tester) async {
      final db = await seeded('open');
      await tester.pumpWidget(
        _app(
          BranchLocationReportsScreen(
            viewer: _person('sup', role: UserRole.admin),
            showAppBar: false,
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('branch_report_reject_d1_br-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('branch_report_reject_confirm')),
      );
      await tester.pump();
      expect(
        find.text(BranchReportsScreenTexts.rejectReasonRequired),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('branch_report_reject_reason')),
        'مكان الفرع صح',
      );
      await tester.tap(
        find.byKey(const ValueKey('branch_report_reject_confirm')),
      );
      await tester.pumpAndSettle();
      final doc = await db
          .collection(kBranchLocationReportsCollection)
          .doc('d1_br-a')
          .get();
      expect(doc.get('status'), 'rejected');
      expect(doc.get('rejectReason'), 'مكان الفرع صح');
    });

    testWidgets('chain admin closes a forwarded report as fixed', (
      tester,
    ) async {
      final db = await seeded('forwarded');
      await tester.pumpWidget(
        _app(
          BranchLocationReportsScreen(
            viewer: _person(
              'oa',
              role: UserRole.organizationAdmin,
              company: '',
            ),
            showAppBar: false,
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('branch_report_forward_d1_br-a')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('branch_report_fixed_d1_br-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(BranchReportsScreenTexts.fixed).last);
      await tester.pumpAndSettle();
      final doc = await db
          .collection(kBranchLocationReportsCollection)
          .doc('d1_br-a')
          .get();
      expect(doc.get('status'), 'fixed');
      expect(doc.get('fixedBy'), 'oa');
    });

    testWidgets('another company\'s supervisor sees nothing; HR is refused', (
      tester,
    ) async {
      final db = await seeded('open');
      await tester.pumpWidget(
        _app(
          BranchLocationReportsScreen(
            viewer: _person('sup2', role: UserRole.admin, company: 'other-co'),
            showAppBar: false,
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('فرع أ'), findsNothing);
      expect(
        find.text(BranchReportsScreenTexts.emptySupervisor),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _app(
          BranchLocationReportsScreen(
            viewer: _person('hr', role: UserRole.hr),
            showAppBar: false,
            repository: BranchLocationReportRepository(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(BranchReportsScreenTexts.noPermission), findsOneWidget);
    });
  });
}
