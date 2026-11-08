import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';

void main() {
  patrolTest(
    'dev: OS location permission dialog (delegate check-in path)',
    ($) async {
      await patrolSetupLoggedInDelegate($);

      final checkIn = find.text('تسجيل الحضور');
      if ($.tester.any(checkIn)) {
        await $.tester.tap(checkIn);
        await $.tester.pump(const Duration(seconds: 1));
      }

      await patrolGrantVisibleOsPermission($);

      await $.tester.pump(const Duration(milliseconds: 800));
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  patrolTest(
    'dev: OS notification permission dialog (post-login FCM)',
    ($) async {
      await patrolSetupLoggedInStaff($);

      await patrolGrantVisibleOsPermission($);

      await $.tester.pump(const Duration(milliseconds: 800));
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
