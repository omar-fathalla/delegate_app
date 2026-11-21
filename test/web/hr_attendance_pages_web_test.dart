// TAS-145, TAS-146, TAS-163, TAS-184: the attendance pages of the web HR
// shell. The detail attendance log is an inner page with a breadcrumb, its
// «سجل تعديلات الحضور» goes to the sidebar tab filtered to the delegate, the
// reason filter is a normal dropdown, the attendance tab has no raw sizes,
// and the status badge does not overflow. Fake data only.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Delegate _person(
  String uid,
  String name, {
  UserRole role = UserRole.delegate,
}) => Delegate(
  uid: uid,
  firstName: name,
  middleName: '',
  lastName: '',
  fullName: name,
  nationalityID: '2900000000${uid.hashCode.abs() % 10000}'.padRight(14, '0'),
  motherName: '',
  city: 'القاهرة',
  phoneNumber: '0100000${uid.hashCode.abs() % 10000}'.padRight(11, '0'),
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1995),
  organizationUID: 'o-fake',
  organizationName: 'سلسلة تجريبية',
  companyUID: 'co-alpha',
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

final _hr = _person('fake-hr', 'مسؤول تجريبي', role: UserRole.hr);
final _subject = _person('fake-d1', 'مندوب تجريبي أول');

void _webDesktop(WidgetTester t, {Size size = const Size(1440, 900)}) {
  WebRuntimePolicy.debugIsWebOverride = true;
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// One unfinished session (the longest badge label) this month.
Future<FakeFirebaseFirestore> _attendanceStore() async {
  final fs = FakeFirebaseFirestore();
  final now = DateTime.now();
  await fs.collection(kAttendanceCollection).doc('in-1').set({
    'delegateId': 'fake-d1',
    'companyId': 'co-alpha',
    'type': 'check_in',
    'timestamp': Timestamp.fromDate(DateTime(now.year, now.month, 1, 9)),
    'branchName': 'فرع تجريبي',
  });
  return fs;
}

Map<String, dynamic> _adjustment(String uid, String name, String reason) {
  final at = Timestamp.fromDate(DateTime(2026, 11, 2, 10));
  return {
    'companyUID': 'co-alpha',
    'delegateUID': uid,
    'delegateName': name,
    'branchName': 'فرع تجريبي',
    'sessionDate': at,
    'originalCheckInTime': at,
    'newCheckInTime': at,
    'adjustedAt': at,
    'reason': reason,
  };
}

Future<FakeFirebaseFirestore> _adjustmentsStore() async {
  final fs = FakeFirebaseFirestore();
  final logs = fs.collection(kAttendanceAdjustmentLogsCollection);
  await logs.doc('a1').set(_adjustment('fake-d1', 'مندوب تجريبي أول', 'نسيان الانصراف'));
  await logs.doc('a2').set(_adjustment('fake-d2', 'مندوب تجريبي ثان', 'خطأ في الجهاز'));
  return fs;
}

/// The wide web shell's content area: a nested navigator with a host.
Widget _shellHost({required String parentTitle, required Widget tab}) {
  final key = GlobalKey<NavigatorState>();
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          const SizedBox(width: 260, child: Text('sidebar')),
          Expanded(
            child: HrInnerPageHost(
              navigatorKey: key,
              parentTitle: parentTitle,
              child: Navigator(
                key: key,
                pages: [MaterialPage<void>(child: Scaffold(body: tab))],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _opener() => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => openHrDelegateAttendanceDetail(
        context,
        delegate: _subject,
        hrDelegate: _hr,
      ),
      child: const Text('open'),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  tearDown(() {
    HRDelegateAttendanceDetailScreen.debugFirestore = null;
    HRAttendanceAdjustmentsScreen.debugFirestore = null;
    HrShellLink.debugReset();
    WebRuntimePolicy.debugReset();
  });

  group('TAS-145: detail log inside the shell', () {
    testWidgets('opens as an inner page with the breadcrumb, no app bar', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await _attendanceStore();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

      await t.pumpWidget(
        _shellHost(parentTitle: 'الحضور والانصراف', tab: _opener()),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(find.text('sidebar'), findsOneWidget);
      final crumb = find.byKey(const ValueKey('hr_inner_page_breadcrumb'));
      expect(
        find.descendant(of: crumb, matching: find.text('الحضور والانصراف')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: crumb, matching: find.text('مندوب تجريبي أول')),
        findsOneWidget,
      );
      final screen = t.widget<HRDelegateAttendanceDetailScreen>(
        find.byType(HRDelegateAttendanceDetailScreen),
      );
      expect(screen.inShell, isTrue);
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const Key('hr_attendance_detail_toolbar')),
        findsOneWidget,
      );
      expect(
        t.getSize(find.byKey(const ValueKey('hr_inner_page_content'))).width,
        lessThanOrEqualTo(HrInnerPageWidth.wide),
      );
      expect(t.takeException(), isNull);

      // Back returns to the tab.
      await t.tap(find.byKey(const ValueKey('hr_inner_page_back')));
      await t.pumpAndSettle();
      expect(find.byType(HRDelegateAttendanceDetailScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('without a shell host it keeps the full-screen app bar', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await _attendanceStore();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

      await t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: _opener()),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('hr_inner_page_breadcrumb')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('hr_attendance_detail_toolbar')),
        findsNothing,
      );
    });
  });

  group('TAS-146: one «سجل تعديلات الحضور»', () {
    testWidgets('the edits button goes to the shell tab for this delegate', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await _attendanceStore();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;
      final requests = <(String, String)>[];
      final bridge = HrWebHeaderBridge();
      addTearDown(bridge.dispose);
      HrShellLink.attach(
        owner: Object(),
        selectTab: (_) {},
        selectMenu: (_) {},
        bridge: bridge,
        openAdjustments: ({required delegateUID, required delegateName}) =>
            requests.add((delegateUID, delegateName)),
      );

      await t.pumpWidget(
        _shellHost(parentTitle: 'الحضور والانصراف', tab: _opener()),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hr_attendance_detail_open_edits')));
      await t.pumpAndSettle();

      expect(requests, [('fake-d1', 'مندوب تجريبي أول')]);
      // No full-screen copy of the log is pushed.
      expect(find.byType(HRAttendanceAdjustmentsScreen), findsNothing);
    });

    test('the shell passes the filter to the sidebar tab', () {
      final filter = HrAdjustmentsDelegateFilter(
        uid: 'fake-d1',
        name: 'مندوب تجريبي أول',
      );
      final tab = hrShellTab(
        index: kHrTabAdjustments,
        delegate: _hr,
        onNavigateToTab: (_) {},
        adjustmentsFilter: filter,
      );
      expect(tab, isA<HRAttendanceAdjustmentsScreen>());
      final screen = tab as HRAttendanceAdjustmentsScreen;
      expect(screen.delegateFilter, same(filter));
      expect(screen.showAppBar, isFalse);
    });

    testWidgets('the tab shows only the filtered delegate until cleared', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await _adjustmentsStore();
      HRAttendanceAdjustmentsScreen.debugFirestore = () => fs;

      Widget build(HrAdjustmentsDelegateFilter? filter) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HRAttendanceAdjustmentsScreen(
            hrDelegate: _hr,
            showAppBar: false,
            delegateFilter: filter,
          ),
        ),
      );

      await t.pumpWidget(
        build(HrAdjustmentsDelegateFilter(uid: 'fake-d1', name: 'مندوب تجريبي أول')),
      );
      await t.pumpAndSettle();

      final chip = find.byKey(const Key('hr_adjustments_delegate_filter'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(
          of: chip,
          matching: find.text('المندوب: مندوب تجريبي أول'),
        ),
        findsOneWidget,
      );
      expect(find.text('مندوب تجريبي ثان'), findsNothing);
      expect(find.text('مندوب تجريبي أول'), findsWidgets);

      // Clearing the chip shows every delegate.
      await t.tap(find.byTooltip('عرض كل المناديب'));
      await t.pumpAndSettle();
      expect(chip, findsNothing);
      expect(find.text('مندوب تجريبي ثان'), findsWidgets);

      // A new request from the shell applies the filter again.
      await t.pumpWidget(
        build(HrAdjustmentsDelegateFilter(uid: 'fake-d2', name: 'مندوب تجريبي ثان')),
      );
      await t.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(find.text('مندوب تجريبي أول'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('«الأسباب» is a normal dropdown, not a full-width bar', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await _adjustmentsStore();
      HRAttendanceAdjustmentsScreen.debugFirestore = () => fs;

      await t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HRAttendanceAdjustmentsScreen(
              hrDelegate: _hr,
              showAppBar: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      final dropdown = find.byKey(const Key('hr_adjustments_reason_filter'));
      expect(dropdown, findsOneWidget);
      expect(t.widget(dropdown), isA<DropdownMenu<String>>());
      expect(t.getSize(dropdown).width, lessThan(400));
      expect(find.text('مندوب تجريبي ثان'), findsWidgets);

      await t.tap(dropdown);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('نسيان الانصراف'),
        ).last,
      );
      await t.pumpAndSettle();

      expect(find.text('مندوب تجريبي أول'), findsWidgets);
      expect(find.text('مندوب تجريبي ثان'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('TAS-184: status badge', () {
    // 800 px is the narrowest table layout; the default test font is much
    // wider than Cairo, like a wider fallback font in a browser.
    for (final size in const [Size(800, 900), Size(1024, 900)]) {
      testWidgets('table: no overflow at ${size.width.toInt()} px (default font)', (
        t,
      ) async {
        _webDesktop(t, size: size);
        final fs = await _attendanceStore();
        HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

        await t.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: HRDelegateAttendanceDetailScreen(
                delegate: _subject,
                hrDelegate: _hr,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();

        final label = find.byKey(const Key('hr_attendance_status_badge_label'));
        expect(label, findsWidgets);
        final text = t.widget<Text>(label.first);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.maxLines, 1);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('TAS-184: approved status colors on web', () {
    Future<FakeFirebaseFirestore> store() async {
      final fs = FakeFirebaseFirestore();
      final logs = fs.collection(kAttendanceCollection);
      Map<String, dynamic> log(String type, DateTime at) => {
        'delegateId': 'fake-d1',
        'companyId': 'co-alpha',
        'type': type,
        'timestamp': Timestamp.fromDate(at),
        'branchName': 'فرع تجريبي',
      };
      // Normal check-out on 1 Oct, a past day left open (auto) on 2 Oct,
      // and a check-in a minute ago (present).
      await logs.doc('in-done').set(log('check_in', DateTime(2026, 10, 1, 9)));
      await logs.doc('out-done').set({
        ...log('check_out', DateTime(2026, 10, 1, 17)),
        'relatedCheckInId': 'in-done',
      });
      await logs.doc('in-auto').set(log('check_in', DateTime(2026, 10, 2, 9)));
      await logs.doc('in-now').set(
        log('check_in', DateTime.now().subtract(const Duration(minutes: 1))),
      );
      return fs;
    }

    BoxDecoration badge(WidgetTester t, String id) {
      final box = t.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key('hr_attendance_status_badge_$id')),
              matching: find.byType(Container),
            )
            .first,
      );
      return box.decoration! as BoxDecoration;
    }

    Future<BuildContext> pump(WidgetTester t, DateTime month) async {
      await t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HRDelegateAttendanceDetailScreen(
              key: ValueKey(month),
              delegate: _subject,
              hrDelegate: _hr,
              initialMonth: month,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      return t.element(find.byType(HRDelegateAttendanceDetailScreen));
    }

    testWidgets('web: check-out = info, auto = warning, present = success', (
      t,
    ) async {
      _webDesktop(t);
      final fs = await store();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

      var context = await pump(t, DateTime(2026, 10));
      var status = HrStatusColors.of(context);
      expect(badge(t, 'in-done').color, status.infoContainer);
      expect(badge(t, 'in-auto').color, status.warningContainer);

      final now = DateTime.now();
      context = await pump(t, DateTime(now.year, now.month));
      status = HrStatusColors.of(context);
      expect(badge(t, 'in-now').color, status.successContainer);
      expect(t.takeException(), isNull);
    });

    testWidgets('mobile keeps its badge colors', (t) async {
      WebRuntimePolicy.debugIsWebOverride = false;
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final fs = await store();
      HRDelegateAttendanceDetailScreen.debugFirestore = () => fs;

      final context = await pump(t, DateTime(2026, 10));
      final cs = Theme.of(context).colorScheme;
      expect(badge(t, 'in-done').color, Colors.green.shade50);
      expect(badge(t, 'in-auto').color, cs.secondaryContainer);
    });
  });

  group('TAS-163: attendance tab tokens', () {
    String body(String source, String signature) {
      final start = source.indexOf(signature);
      expect(start, isNonNegative, reason: signature);
      final next = source.indexOf(RegExp(r'\n  Widget '), start + 10);
      return source.substring(start, next < 0 ? source.length : next);
    }

    test('date card, KPI cards and time group use HR tokens', () {
      final source = File(
        'lib/features/hr/presentation/pages/tabs/hr_attendance_tab.dart',
      ).readAsStringSync();
      for (final signature in const [
        'Widget _buildKpiCard(',
        'Widget _buildDateCard(',
        'Widget _buildTimeHoursGroup(',
      ]) {
        final code = body(source, signature);
        expect(
          RegExp(r'fontSize:\s*(isWide\s*\?\s*)?\d').hasMatch(code),
          isFalse,
          reason: '$signature has a raw font size',
        );
        expect(
          RegExp(r':\s*\d+(\.\d+)?\s*,\s*$', multiLine: true)
              .allMatches(code)
              .where((m) => code
                  .substring(code.lastIndexOf('\n', m.start) + 1, m.start)
                  .contains('fontSize'))
              .isEmpty,
          isTrue,
          reason: '$signature has a raw font size in a ternary',
        );
        expect(code.contains('Colors.amber'), isFalse, reason: signature);
        expect(
          RegExp(r'BorderRadius\.circular\(\d').hasMatch(code),
          isFalse,
          reason: '$signature has a raw radius',
        );
      }
    });
  });
}
