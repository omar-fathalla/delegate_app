import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';

void main() {
  patrolTest(
    'dev: notification shade opens after staff session',
    ($) async {
      await patrolSetupLoggedInStaff($);

      await patrolGrantVisibleOsPermission($);
      await patrolOpenNotificationShade($);
      await patrolBackgroundAndForeground($);

      await $.tester.pump(const Duration(seconds: 2));
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
