import 'package:delegate_app/main.dart' show MyApp, bootstrapDelegateAppForPatrol;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_dev_credentials.dart';
import 'support/smoke_dummy_login.dart';

void main() {
  patrolTest(
    'dev flavor: tashil-dev dummy login and supervisor role',
    ($) async {
      await bootstrapDelegateAppForPatrol();
      await $.pumpWidget(const MyApp());

      expect(Firebase.app().options.projectId, 'tashil-dev');

      final creds = SmokeDevPatrolCredentials.fromEnvironment();
      await submitDevDummyLogin($, creds);
      await verifyDevLoggedInRole($, creds);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
