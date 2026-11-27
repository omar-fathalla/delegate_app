import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';
import 'support/smoke_dev_credentials.dart';
import 'support/smoke_dummy_login.dart';

/// TAS-393: marketing (role `marketing`) on a real simulator.
///
/// Login (staff screen) + the post-login notification prompt, then the
/// Branches tab: floor-check today's first seeded delegate, confirm the write
/// reached Firestore under the live tashil-dev rules, survive a trip to the
/// background, and undo the check so the next run starts clean.
///
/// Data: `functions/scripts/seed-marketing-journey-attendance.js` (the mac-gate
/// runs it before Patrol). Account: `PATROL_DEV_MARKETING_SECRET`; without it
/// the test is skipped.
const _branch = 'Fake Branch Alpha';
const _delegateId = 'seed-fake-del-alpha-1';

Future<void> _pumpUntilFound(
  PatrolIntegrationTester $,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await $.tester.pump(const Duration(milliseconds: 250));
    if ($.tester.any(finder)) return;
  }
  fail('Timed out waiting for $finder');
}

Future<DocumentSnapshot<Map<String, dynamic>>> _floorCheckDoc() {
  final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return FirebaseFirestore.instance
      .collection('floor_checks')
      .doc('${day}_${_branch}_$_delegateId')
      .get(const GetOptions(source: Source.server));
}

void main() {
  final creds = SmokeDevPatrolCredentials.marketingFromEnvironment();

  patrolTest(
    'dev: marketing floor check survives background (TAS-393)',
    ($) async {
      await patrolBootstrapDevApp($);
      await submitDevDummyLogin($, creds);
      await patrolGrantVisibleOsPermission($);
      await $.tester.pump(const Duration(milliseconds: 800));
      expect(patrolMainMenuButtonFinder(), findsWidgets);

      // Branches tab (bottom navigation).
      await $.tester.tap(find.text('الفروع').last);
      await $.tester.pump(const Duration(seconds: 1));

      // Fresh install: no favourite branch yet, the tab opens the picker.
      final pickerItem = find.text(_branch);
      await _pumpUntilFound($, pickerItem);
      if ($.tester.any(find.text('ابحث عن فرع...'))) {
        await $.tester.tap(pickerItem.last);
        await $.tester.pump(const Duration(seconds: 1));
      }

      final check = find.byKey(const ValueKey('floor_check_$_delegateId'));
      // Rows are a lazy SliverList (newest check-in first), so the seeded
      // 08:05 delegate can sit below the fold: wait for the list, then scroll.
      await _pumpUntilFound(
        $,
        find.byKey(const ValueKey('branch_header_$_branch')),
        timeout: const Duration(seconds: 90),
      );
      await $(
        check,
      ).scrollTo(maxScrolls: 30, settlePolicy: SettlePolicy.trySettle);

      bool selected() => $.tester.widget<FilterChip>(check).selected;
      // Leave a clean state whatever an earlier run left behind.
      if (selected()) {
        await $.tester.tap(check);
        await $.tester.pump(const Duration(seconds: 2));
      }

      await $.tester.tap(check);
      await $.tester.pump(const Duration(seconds: 2));
      expect(selected(), isTrue, reason: 'chip shows the delegate as checked');

      // The write is fire-and-forget; poll the server copy (rules accepted).
      var stored = await _floorCheckDoc();
      for (var i = 0; i < 20 && !stored.exists; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        stored = await _floorCheckDoc();
      }
      expect(stored.exists, isTrue, reason: 'floor_checks doc written');
      expect(stored.data()?['status'], 'verified');

      await patrolBackgroundAndForeground($);
      await $.tester.pump(const Duration(seconds: 2));
      await $(
        check,
      ).scrollTo(maxScrolls: 30, settlePolicy: SettlePolicy.trySettle);
      expect(selected(), isTrue, reason: 'check kept after resume');

      // Undo so the next run starts unchecked.
      await $.tester.tap(check);
      await $.tester.pump(const Duration(seconds: 2));
      expect(selected(), isFalse);
    },
    skip: !creds.hasSecret,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
