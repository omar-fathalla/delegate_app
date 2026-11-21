// HR web «تدقيق الأمان» and «فك الأجهزة» (TAS-153, TAS-154): the audit page
// shows the fraud log only and searches as the user types; the unbind page
// uses theme buttons at the card's end, the primary container for the
// selected stat card and the shared dialog; the narrow web menu puts the
// pending count beside the label. Admin roles and mobile keep their layout.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/hr/presentation/device_unbind_labels.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_web_overflow_menu.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
// Transitive test helper of firebase_core (fake Firebase app, no network).
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _company = 'seed-fake-co-alpha';

Delegate _hr() => Delegate(
  uid: 'seed-fake-hr',
  firstName: 'موظف',
  middleName: '',
  lastName: 'وهمي',
  fullName: 'موظف وهمي',
  nationalityID: '__firebase_auth__:fake@example.com',
  motherName: '',
  city: '',
  phoneNumber: '01000000006',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-hr-org',
  organizationName: 'Fake Test Organization',
  companyUID: _company,
  companyName: 'Fake Company Alpha',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.hr,
  email: 'fake@example.com',
);

ThemeData _theme() => AppTheme.lightTheme();

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: _theme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('ar'),
  home: home,
);

/// Screens also read branches and companies from the default instance; with
/// no native side those reads simply never answer.
void _silenceFirestore() {
  const api =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  for (final method in const [
    'querySnapshot',
    'queryGet',
    'aggregateQuery',
    'documentReferenceSnapshot',
    'documentReferenceGet',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          '$api.$method',
          (_) => Completer<ByteData?>().future,
        );
  }
}

void _desktop(WidgetTester t) {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<FakeFirebaseFirestore> _auditDb() async {
  final db = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime(2026, 11, 20, 10));
  await db.collection('security_audit_logs').add({
    'companyUID': _company,
    'delegateUid': 'd1',
    'delegateName': 'أحمد سالم',
    'delegatePhone': '01000000001',
    'deviceModel': 'Pixel 7',
    'timestamp': now,
  });
  await db.collection('security_audit_logs').add({
    'companyUID': _company,
    'delegateUid': 'd2',
    'delegateName': 'محمود فؤاد',
    'delegatePhone': '01000000002',
    'deviceModel': 'Galaxy A54',
    'timestamp': now,
  });
  return db;
}

Future<FakeFirebaseFirestore> _unbindDb() async {
  final db = FakeFirebaseFirestore();
  await db.collection('device_unbind_requests').add({
    'companyUID': _company,
    'status': 'pending',
    'delegateUid': 'd1',
    'delegateName': 'أحمد سالم',
    'delegatePhone': '01000000001',
    'boundDeviceModel': 'Pixel 7',
    'requestedDeviceModel': 'Pixel 8',
    'createdAt': Timestamp.fromDate(DateTime(2026, 11, 20, 9)),
  });
  await db.collection('device_unbind_requests').add({
    'companyUID': _company,
    'status': 'pending',
    'delegateUid': 'd2',
    'delegateName': 'محمود فؤاد',
    'delegatePhone': '01000000002',
    'boundDeviceModel': 'Galaxy A54',
    'requestedDeviceModel': 'Galaxy S24',
    'createdAt': Timestamp.fromDate(DateTime(2026, 11, 20, 8)),
  });
  return db;
}

Future<void> _pumpAudit(
  WidgetTester t,
  FakeFirebaseFirestore db, {
  required bool hrWebLayout,
}) async {
  await t.pumpWidget(
    _app(
      Scaffold(
        body: AntiFraudAuditScreen(
          delegate: _hr(),
          showAppBar: false,
          hrWebLayout: hrWebLayout,
          firestore: db,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpUnbind(WidgetTester t, FakeFirebaseFirestore db) async {
  await t.pumpWidget(
    _app(
      Scaffold(
        body: HRDeviceUnbindRequestsScreen(
          hrDelegate: _hr(),
          showAppBar: false,
          firestore: db,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    _silenceFirestore();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebRuntimePolicy.debugIsWebOverride = true;
  });

  tearDown(() => WebRuntimePolicy.debugIsWebOverride = null);

  group('TAS-153 security audit in the HR web shell', () {
    test('the HR shell tab passes the web layout on web only', () {
      final web = hrShellTab(
        index: kHrTabFraud,
        delegate: _hr(),
        onNavigateToTab: (_) {},
      );
      expect((web as AntiFraudAuditScreen).hrWebLayout, isTrue);

      WebRuntimePolicy.debugIsWebOverride = false;
      final mobile = hrShellTab(
        index: kHrTabFraud,
        delegate: _hr(),
        onNavigateToTab: (_) {},
      );
      expect((mobile as AntiFraudAuditScreen).hrWebLayout, isFalse);
    });

    testWidgets('shows the fraud log only, no device binding card', (t) async {
      _desktop(t);
      await _pumpAudit(t, await _auditDb(), hrWebLayout: true);

      expect(find.text('منظومة كشف التزييف والأمان'), findsOneWidget);
      expect(find.text('ربط أجهزة المناديب'), findsNothing);
      expect(find.text('أقسام الرقابة'), findsNothing);
      expect(find.text('سجلات كشف التزييف'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('admin layout keeps the section switcher', (t) async {
      _desktop(t);
      await _pumpAudit(t, await _auditDb(), hrWebLayout: false);

      expect(find.text('ربط أجهزة المناديب'), findsOneWidget);
      expect(find.byTooltip('تنفيذ البحث'), findsOneWidget);
    });
  });

  group('TAS-154 security audit search', () {
    testWidgets('filters as the user types, no search button', (t) async {
      _desktop(t);
      await _pumpAudit(t, await _auditDb(), hrWebLayout: true);

      expect(find.byTooltip('تنفيذ البحث'), findsNothing);
      expect(find.textContaining('أحمد سالم'), findsWidgets);
      expect(find.textContaining('محمود فؤاد'), findsWidgets);

      await t.enterText(find.byType(TextField).first, 'محمود');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('أحمد سالم'), findsNothing);
      expect(find.textContaining('محمود فؤاد'), findsWidgets);
      // The field keeps its focus while the list filters.
      final field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'محمود');
      expect(t.takeException(), isNull);
    });
  });

  group('TAS-154 device unbind requests on web', () {
    testWidgets('approve is a FilledButton and reject an OutlinedButton, '
        'at their own width and at the card end', (t) async {
      _desktop(t);
      await _pumpUnbind(t, await _unbindDb());

      final approve = find.byKey(const ValueKey('device_unbind_approve'));
      final reject = find.byKey(const ValueKey('device_unbind_reject'));
      expect(approve, findsNWidgets(2));
      expect(reject, findsNWidgets(2));

      expect(
        find.descendant(
          of: approve.first,
          matching: find.text(DeviceUnbindLabels.approve),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: reject.first,
          matching: find.text(DeviceUnbindLabels.reject),
        ),
        findsOneWidget,
      );
      expect(DeviceUnbindLabels.approve, 'فك الارتباط');
      expect(DeviceUnbindLabels.reject, 'رفض');
      expect(find.text('اعتماد وفك الارتباط'), findsNothing);
      expect(find.text('موافقة وفك الارتباط'), findsNothing);
      expect(find.text('رفض الطلب'), findsNothing);

      final approveWidget = t.widget(approve.first);
      final rejectWidget = t.widget(reject.first);
      expect(approveWidget, isA<FilledButton>());
      expect(rejectWidget, isA<OutlinedButton>());
      // Theme colors, no custom style.
      expect((approveWidget as FilledButton).style, isNull);
      expect((rejectWidget as OutlinedButton).style, isNull);

      // Normal width, not stretched across the card.
      expect(t.getSize(approve.first).width, lessThan(320));
      expect(t.getSize(reject.first).width, lessThan(200));

      // At the card's end: in RTL the end is the left side, so both buttons
      // sit in the left half of the page.
      expect(t.getRect(approve.first).right, lessThan(720));
      expect(t.getRect(reject.first).right, lessThan(720));
      expect(t.takeException(), isNull);
    });

    testWidgets('selected stat card uses the primary container', (t) async {
      _desktop(t);
      await _pumpUnbind(t, await _unbindDb());

      final scheme = _theme().colorScheme;
      BoxDecoration cardOf(String title) {
        final box = t.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(title),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        return box.decoration! as BoxDecoration;
      }

      // «قيد المراجعة» is selected by default and has pending requests,
      // which used to tint it orange.
      expect(cardOf('قيد المراجعة').color, scheme.primaryContainer);
      expect(cardOf('المعتمدة').color, isNot(scheme.primaryContainer));

      await t.tap(find.text('المعتمدة'));
      await t.pump(const Duration(milliseconds: 400));
      expect(cardOf('المعتمدة').color, scheme.primaryContainer);
      expect(cardOf('قيد المراجعة').color, isNot(scheme.primaryContainer));
    });

    testWidgets('search filters as the user types', (t) async {
      _desktop(t);
      await _pumpUnbind(t, await _unbindDb());

      expect(find.text('أحمد سالم'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Galaxy');
      await t.pump();
      expect(find.text('أحمد سالم'), findsNothing);
      expect(find.text('محمود فؤاد'), findsOneWidget);
    });

    testWidgets('approve and reject confirm in the shared HR dialog', (
      t,
    ) async {
      _desktop(t);
      await _pumpUnbind(t, await _unbindDb());

      await t.tap(find.byKey(const ValueKey('device_unbind_approve')).first);
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(DeviceUnbindLabels.approveTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey('device_unbind_confirm_approve')),
        findsOneWidget,
      );
      await t.tap(find.text(DeviceUnbindLabels.cancel));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await t.tap(find.byKey(const ValueKey('device_unbind_reject')).first);
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(DeviceUnbindLabels.rejectTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey('device_unbind_confirm_reject')),
        findsOneWidget,
      );
      await t.tap(find.text(DeviceUnbindLabels.cancel));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('mobile keeps the full-width buttons with the shared labels', (
      t,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = false;
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await _pumpUnbind(t, await _unbindDb());

      expect(find.byKey(const ValueKey('device_unbind_approve')), findsNothing);
      // Owner decision: the same labels on mobile and web.
      expect(find.text(DeviceUnbindLabels.approve), findsNWidgets(2));
      expect(find.text(DeviceUnbindLabels.reject), findsNWidgets(2));
      expect(find.text('اعتماد وفك الارتباط'), findsNothing);
      expect(find.text('رفض الطلب'), findsNothing);
      // Layout unchanged: the approve button still fills its Expanded slot.
      final approve = find.ancestor(
        of: find.text(DeviceUnbindLabels.approve).first,
        matching: find.byType(Expanded),
      );
      expect(approve, findsWidgets);
    });
  });

  group('TAS-154 narrow web menu count', () {
    testWidgets('pending count sits beside the label, not on the icon', (
      t,
    ) async {
      t.view.physicalSize = const Size(700, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        _app(
          Scaffold(
            appBar: AppBar(
              actions: [
                HrWebOverflowMenu(
                  delegate: _hr(),
                  currentIndex: kHrTabAttendance,
                  onSelected: (_) {},
                  trailingFor: (item) =>
                      item.badgeCollection == 'device_unbind_requests'
                      ? const Text('3', key: ValueKey('devices_count'))
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byType(IconButton).last);
      await t.pumpAndSettle();

      final row = find.byKey(
        const ValueKey('hr_web_overflow_device_unbind_requests'),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('devices_count')),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.byType(Badge)), findsNothing);
    });
  });
}
