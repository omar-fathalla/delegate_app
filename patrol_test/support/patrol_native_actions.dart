// ignore_for_file: deprecated_member_use_from_same_package

import 'package:patrol/patrol.dart';

const Duration patrolSavePasswordPollStep = Duration(milliseconds: 400);
const Duration patrolSavePasswordPollWindow = Duration(seconds: 20);

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

/// Dismisses the iOS system Save Password sheet when it covers the Flutter layer.
Future<void> patrolDismissIosSavePasswordSheet(PatrolIntegrationTester $) async {
  final end = DateTime.now().add(patrolSavePasswordPollWindow);
  while (DateTime.now().isBefore(end)) {
    for (final label in const ['Not Now', 'ليس الآن', 'Never', 'أبداً']) {
      try {
        await $.native.tap(
          Selector(text: label),
          timeout: const Duration(milliseconds: 600),
        );
        await Future<void>.delayed(patrolSavePasswordPollStep);
      } catch (_) {}
    }
    await Future<void>.delayed(patrolSavePasswordPollStep);
  }
}
