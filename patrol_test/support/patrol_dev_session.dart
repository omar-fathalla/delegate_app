import 'package:delegate_app/main.dart' show MyApp, bootstrapDelegateAppForPatrol;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'smoke_dev_credentials.dart';
import 'smoke_dummy_login.dart';

/// Boots tashil-dev flavor for Patrol (no login journey assertions).
Future<void> patrolBootstrapDevApp(PatrolIntegrationTester $) async {
  await bootstrapDelegateAppForPatrol();
  await $.pumpWidget(const MyApp());
  expect(Firebase.app().options.projectId, 'tashil-dev');
}

/// Logged-in staff session — shared setup for native integration tests.
Future<void> patrolSetupLoggedInStaff(PatrolIntegrationTester $) async {
  final creds = SmokeDevPatrolCredentials.staffFromEnvironment();
  expect(creds.hasSecret, isTrue, reason: 'Set PATROL_DEV_SECRET via dart-define');
  await patrolBootstrapDevApp($);
  await submitDevDummyLogin($, creds);
}

/// Logged-in delegate session — shared setup for attendance / location tests.
Future<void> patrolSetupLoggedInDelegate(PatrolIntegrationTester $) async {
  final creds = SmokeDevPatrolCredentials.delegateFromEnvironment();
  await patrolBootstrapDevApp($);
  await submitDevDelegateDummyLogin($, creds);
}

Finder patrolMainMenuButtonFinder() =>
    find.bySemanticsIdentifier('tashil_main_menu_button');
