import 'package:delegate_app/main.dart' show MyApp, bootstrapDelegateAppForPatrol;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_login_wait.dart';

void main() {
  patrolTest(
    'dev flavor: splash stall sign in login screen visible',
    ($) async {
      await bootstrapDelegateAppForPatrol();
      await $.pumpWidget(const MyApp());

      expect(Firebase.app().options.projectId, 'tashil-dev');

      await waitForDevLoginScreenAfterSplash($);

      final semantics = devLoginScreenSemanticsFinder();
      if ($.tester.any(semantics)) {
        await $(semantics).waitUntilVisible(
          timeout: smokeLoginVisibleTimeout,
        );
        expect($(semantics), findsOneWidget);
        return;
      }

      final phoneIcon = devLoginPhoneFieldIconFinder();
      await $(phoneIcon).waitUntilVisible(timeout: smokeLoginVisibleTimeout);
      expect($(phoneIcon), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
