import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';
import 'support/smoke_dev_credentials.dart';
import 'support/smoke_dummy_login.dart';

/// TAS-393: marketing actions that leave the Flutter layer or write data.
///
/// 1. Branch Excel export opens the OS share sheet (the app goes inactive)
///    and coming back leaves the app usable.
/// 2. «تعديل المدة» on a photo permission writes the new end date to
///    Firestore under the live tashil-dev rules.
///
/// Data: `functions/scripts/seed-marketing-journey-data.js` (mac-gate runs it
/// first; it also puts the permission dates back). Account:
/// `PATROL_DEV_MARKETING_SECRET`; without it the tests are skipped.
const _branch = 'Fake Branch Alpha';
const _permissionPath =
    'organizations/seed-fake-hr-org/companies/seed-fake-co-alpha/photo_permissions/seed-fake-tas392-pp1';

Future<void> _pumpUntil(
  PatrolIntegrationTester $,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await $.tester.pump(const Duration(milliseconds: 250));
    if (done()) return;
  }
  fail('Timed out waiting for $what');
}

Future<void> _loginMarketing(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  await patrolBootstrapDevApp($);
  // Tests in one file share app data (clearPackageData is off), so the
  // second test can start already signed in.
  await _pumpUntil(
    $,
    () =>
        $.tester.any(patrolMainMenuButtonFinder()) ||
        $.tester.any(find.text('موظف إداري')),
    what: 'login screen or home',
  );
  if (!$.tester.any(patrolMainMenuButtonFinder())) {
    await submitDevDummyLogin($, creds);
  }
  await patrolGrantVisibleOsPermission($);
  await $.tester.pump(const Duration(milliseconds: 800));
  expect(patrolMainMenuButtonFinder(), findsWidgets);
}

void main() {
  final creds = SmokeDevPatrolCredentials.marketingFromEnvironment();

  patrolTest(
    'dev: marketing branch Excel export opens the share sheet (TAS-393)',
    ($) async {
      await _loginMarketing($, creds);

      await $.tester.tap(find.text('الفروع').last);
      await $.tester.pump(const Duration(seconds: 1));
      await _pumpUntil(
        $,
        () => $.tester.any(find.text(_branch)),
        what: 'branch picker or header',
      );
      if ($.tester.any(find.text('ابحث عن فرع...'))) {
        await $.tester.tap(find.text(_branch).last);
        await $.tester.pump(const Duration(seconds: 1));
      }
      final menu = find.byTooltip('خيارات الفرع');
      await _pumpUntil($, () => $.tester.any(menu), what: 'branch menu');

      await $.tester.tap(menu.first);
      await $.tester.pump(const Duration(milliseconds: 600));
      await $.tester.tap(find.text('تصدير كشف الفرع (Excel)'));
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.tap(find.textContaining('كشف الحضور الكامل'));
      await $.tester.pump(const Duration(milliseconds: 400));
      await $.tester.tap(find.text('تصدير Excel'));

      if (Platform.isIOS) {
        // TAS-394: on iOS the share sheet is a view controller inside the
        // app, so the lifecycle stays resumed and there is no Back button.
        // Find the sheet natively and close it with its own button.
        await $.native.waitUntilVisible(
          Selector(text: 'Save to Files'),
          timeout: const Duration(seconds: 20),
        );
        await $.native.tap(
          Selector(text: 'Close'),
          timeout: const Duration(seconds: 10),
        );
        await $.tester.pump(const Duration(seconds: 1));
      } else {
        // Android: the OS share sheet takes the foreground, so the app is no
        // longer resumed.
        await _pumpUntil(
          $,
          () =>
              WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed,
          timeout: const Duration(seconds: 20),
          what: 'the OS share sheet',
        );
        await $.native.pressBack();
      }
      await _pumpUntil(
        $,
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        timeout: const Duration(seconds: 20),
        what: 'the app to resume',
      );
      expect(find.textContaining('تعذّر'), findsNothing);
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    skip: !creds.hasSecret,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  patrolTest(
    'dev: marketing edits a photo permission end date (TAS-393)',
    ($) async {
      await _loginMarketing($, creds);
      final doc = FirebaseFirestore.instance.doc(_permissionPath);
      final before = await doc.get(const GetOptions(source: Source.server));
      final start = (before.data()!['startDate'] as Timestamp).toDate();

      await $.tester.tap(find.text('أذونات التصوير').last);
      await $.tester.pump(const Duration(seconds: 1));
      final options = find.byTooltip('خيارات الإذن');
      await _pumpUntil($, () => $.tester.any(options), what: 'permission card');

      await $.tester.tap(options.first);
      await $.tester.pump(const Duration(milliseconds: 600));
      await $.tester.tap(find.text('تعديل المدة'));
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.tap(find.text('30 يوم'));
      await $.tester.pump(const Duration(milliseconds: 400));
      await $.tester.tap(find.text('حفظ المدة الجديدة'));
      await $.tester.pump(const Duration(seconds: 2));

      // The server copy now ends 30 days after the start (rules accepted it).
      var days = 0;
      for (var i = 0; i < 20; i++) {
        final after = await doc.get(const GetOptions(source: Source.server));
        final end = (after.data()!['endDate'] as Timestamp).toDate();
        days = end.difference(start).inDays;
        if (days >= 29) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(
        days,
        inInclusiveRange(29, 31),
        reason: 'endDate = start + 30 days',
      );
    },
    skip: !creds.hasSecret,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
