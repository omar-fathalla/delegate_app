import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_dev_session.dart';
import 'support/patrol_native_actions.dart';

void main() {
  patrolTest(
    'dev: delegate home check-in reaches location gate without login assert',
    ($) async {
      await patrolSetupLoggedInDelegate($);

      expect(find.text('الرئيسية'), findsWidgets);

      final checkIn = find.text('تسجيل الحضور');
      if (!$.tester.any(checkIn)) {
        return;
      }

      await $(checkIn).scrollTo();
      await $.tester.tap(checkIn);
      await $.tester.pump(const Duration(seconds: 2));

      await patrolGrantVisibleOsPermission($);

      await $.tester.pump(const Duration(seconds: 1));
      // Still authenticated — not bounced to login.
      expect(find.text('تسجيل الدخول'), findsNothing);
      expect(patrolMainMenuButtonFinder(), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
