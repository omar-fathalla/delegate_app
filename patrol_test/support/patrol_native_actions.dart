// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:ui';

import 'package:patrol/patrol.dart';

const Duration patrolSavePasswordPollStep = Duration(milliseconds: 350);
const Duration patrolSavePasswordPollWindow = Duration(seconds: 24);

const List<String> _iosSavePasswordDismissLabels = [
  'Not Now',
  'ليس الآن',
  "Don't Save",
  'Never',
  'Never for This Website',
  'أبداً',
  'عدم الحفظ',
];

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
    for (final label in _iosSavePasswordDismissLabels) {
      try {
        await $.native.tap(
          Selector(text: label),
          timeout: const Duration(milliseconds: 450),
        );
        await Future<void>.delayed(patrolSavePasswordPollStep);
      } catch (_) {}
    }
    for (final offset in const [
      Offset(120, 660),
      Offset(280, 660),
    ]) {
      try {
        await $.native.tapAt(offset);
        await Future<void>.delayed(patrolSavePasswordPollStep);
      } catch (_) {}
    }
    await Future<void>.delayed(patrolSavePasswordPollStep);
  }
}
