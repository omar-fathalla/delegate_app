// TAS-120: «سجل الحضور التفصيلي» must query attendance scoped to the HR
// user's company (the rules reject an unscoped delegateId/userId query for
// company staff), and a failed load shows a clear Arabic message, never the
// raw Firebase text. Fake data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Delegate _person(String uid, String company, {UserRole role = UserRole.delegate}) =>
    Delegate(
      uid: uid,
      firstName: 'تجريبي',
      middleName: '',
      lastName: '',
      fullName: 'مندوب تجريبي',
      nationalityID: '29000000000099',
      motherName: '',
      city: 'القاهرة',
      phoneNumber: '01000000099',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1995),
      organizationUID: 'o-fake',
      organizationName: 'سلسلة تجريبية',
      companyUID: company,
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

/// Every read fails the way the rules reject an unprovable query.
class _DeniedFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    // Real glyph widths (the default test font is much wider for Arabic).
    final cairo = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
    await cairo.load();
  });

  tearDown(() {
    HRDelegateAttendanceDetailScreen.debugFirestore = null;
    WebRuntimePolicy.debugReset();
  });

  test('query is scoped to the HR company (delegateId and legacy userId)',
      () async {
    final fs = FakeFirebaseFirestore();
    final logs = fs.collection(kAttendanceCollection);
    await logs.doc('own-in').set({
      'delegateId': 'fake-d1',
      'companyId': 'co-alpha',
      'type': 'check_in',
    });
    await logs.doc('own-legacy').set({
      'userId': '01000000099',
      'companyId': 'co-alpha',
      'type': 'check_in',
    });
    await logs.doc('other-company').set({
      'delegateId': 'fake-d1',
      'companyId': 'co-beta',
      'type': 'check_in',
    });

    final docs = await fetchDelegateAttendanceDocs(
      firestore: fs,
      identifiers: const ['fake-d1', '01000000099'],
      companyId: 'co-alpha',
    );
    expect(docs.keys.toSet(), {'own-in', 'own-legacy'});
  });

  test('permission-denied becomes a clear Arabic message', () {
    final msg = hrAttendanceLoadErrorMessage(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      ),
    );
    expect(msg, 'ليس لديك صلاحية لعرض سجل حضور هذا المندوب.');
    expect(msg, isNot(contains('permission')));
    expect(
      hrAttendanceLoadErrorMessage(Exception('boom')),
      isNot(contains('boom')),
    );
  });

  testWidgets('web: a denied load shows HrEmptyState, not the Firebase text',
      (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    HRDelegateAttendanceDetailScreen.debugFirestore = () => _DeniedFirestore();

    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HRDelegateAttendanceDetailScreen(
            delegate: _person('fake-d1', 'co-alpha'),
            hrDelegate: _person('fake-hr', 'co-alpha', role: UserRole.hr),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.byKey(const Key('hr_attendance_detail_error')), findsOneWidget);
    expect(find.byType(HrEmptyState), findsOneWidget);
    expect(find.text('تعذر تحميل سجل الحضور'), findsOneWidget);
    expect(
      find.text('ليس لديك صلاحية لعرض سجل حضور هذا المندوب.'),
      findsOneWidget,
    );
    expect(find.textContaining('permission'), findsNothing);
    expect(find.textContaining('cloud_firestore'), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('web: a scoped load shows the HR company sessions', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final fs = FakeFirebaseFirestore();
    final now = DateTime.now();
    await fs.collection(kAttendanceCollection).doc('in-1').set({
      'delegateId': 'fake-d1',
      'companyId': 'co-alpha',
      'type': 'check_in',
      'timestamp': Timestamp.fromDate(DateTime(now.year, now.month, 1, 9)),
      'branchName': 'فرع تجريبي',
    });
    await fs.collection(kAttendanceCollection).doc('out-1').set({
      'delegateId': 'fake-d1',
      'companyId': 'co-alpha',
      'type': 'check_out',
      'relatedCheckInId': 'in-1',
      'timestamp': Timestamp.fromDate(DateTime(now.year, now.month, 1, 17)),
      'branchName': 'فرع تجريبي',
    });
    HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HRDelegateAttendanceDetailScreen(
            delegate: _person('fake-d1', 'co-alpha'),
            hrDelegate: _person('fake-hr', 'co-alpha', role: UserRole.hr),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hr_attendance_detail_error')), findsNothing);
    expect(find.textContaining('فرع تجريبي'), findsWidgets);
  });
}
