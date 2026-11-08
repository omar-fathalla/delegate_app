import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';

void main() {
  patrolTest(
    'dev: background/foreground keeps session (Workmanager offlineSyncTask registered)',
    ($) async {
      await patrolSetupLoggedInStaff($);

      // Let post-launch Workmanager registration run ([main.dart] ~8s delay).
      await $.tester.pump(const Duration(seconds: 9));

      await patrolBackgroundAndForeground($);

      await $.tester.pump(const Duration(seconds: 2));
      expect(find.text('تسجيل الدخول'), findsNothing);
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
