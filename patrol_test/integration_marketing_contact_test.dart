import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';
import 'support/smoke_dev_credentials.dart';
import 'support/smoke_dummy_login.dart';

/// TAS-393: marketing contacts a delegate's supervisor from the branches tab.
/// «اتصال الآن» opens the phone dialer (number filled, no call is placed) and
/// «واتساب» opens a wa.me chat (nothing is sent); the test returns to the app
/// each time. Android only: the iOS simulator has no Phone / WhatsApp app.
///
/// Data: `functions/scripts/seed-marketing-journey-data.js` (today's check-in
/// of seed-fake-del-alpha-1, whose company supervisor is a fake user).
const _branch = 'Fake Branch Alpha';
const _delegateId = 'seed-fake-del-alpha-1';

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

bool _resumed() =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

/// Waits for the lifecycle with plain delays: `tester.pump` blocks while the
/// app is in the background (no frames are drawn there).
Future<void> _waitLifecycle(bool Function() done, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('Timed out waiting for $what');
}

/// Leaves the external app (the Samsung dialer does not close on back) and
/// waits until Tashil is in front again.
Future<void> _backToApp(PatrolIntegrationTester $) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  await $.native.openApp();
  await _waitLifecycle(_resumed, 'the app to resume');
  await $.tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openSupervisorSheet(PatrolIntegrationTester $) async {
  final call = find.byKey(const ValueKey('call_supervisor_$_delegateId'));
  await $(call).scrollTo(maxScrolls: 30, settlePolicy: SettlePolicy.trySettle);
  await $.tester.tap(call);
  await _pumpUntil(
    $,
    () => $.tester.any(find.text('الاتصال بمشرف المندوب')),
    what: 'the supervisor sheet',
  );
  expect(
    find.textContaining('لا يوجد رقم هاتف'),
    findsNothing,
    reason: 'the fake supervisor must have a phone',
  );
}

void main() {
  final creds = SmokeDevPatrolCredentials.marketingFromEnvironment();

  patrolTest(
    'dev: marketing calls and WhatsApps a delegate supervisor (TAS-393)',
    ($) async {
      await patrolBootstrapDevApp($);
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

      // Phone dialer.
      await _openSupervisorSheet($);
      await $.tester.tap(find.text('اتصال الآن'));
      await _pumpUntil(
        $,
        () => !_resumed(),
        timeout: const Duration(seconds: 20),
        what: 'the phone dialer',
      );
      await _backToApp($);

      // WhatsApp chat (wa.me); nothing is sent.
      if (!$.tester.any(find.text('واتساب'))) await _openSupervisorSheet($);
      await $.tester.tap(find.text('واتساب'));
      await _pumpUntil(
        $,
        () => !_resumed(),
        timeout: const Duration(seconds: 20),
        what: 'WhatsApp / browser',
      );
      await _backToApp($);

      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    skip: !creds.hasSecret || !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
