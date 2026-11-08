// ignore_for_file: deprecated_member_use_from_same_package

import 'package:patrol/patrol.dart';

Future<void> patrolGrantVisibleOsPermission(PatrolIntegrationTester $) async {
  try {
    await $.native.grantPermissionWhenInUse();
  } catch (_) {}
}

Future<void> patrolBackgroundAndForeground(PatrolIntegrationTester $) async {
  await $.native.pressHome();
  await Future<void>.delayed(const Duration(seconds: 2));
  await $.native.openApp();
}

Future<void> patrolOpenNotificationShade(PatrolIntegrationTester $) async {
  await $.native.openNotifications();
}
