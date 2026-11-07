import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'smoke_dev_credentials.dart';
import 'smoke_login_wait.dart';

const Duration smokeLoginFieldTimeout = Duration(seconds: 30);
const Duration smokePostLoginDeadline = Duration(seconds: 120);
const Duration smokePostLoginPumpStep = Duration(milliseconds: 250);

Finder devLoginPhoneLabelFinder() => find.text('رقم الجوال');
Finder devLoginSecretLabelFinder() => find.text('الرقم القومي');
Finder devLoginSubmitSemanticsFinder() =>
    find.bySemanticsIdentifier('tashil_login_submit');
Finder devMainMenuButtonFinder() =>
    find.bySemanticsIdentifier('tashil_main_menu_button');
Finder devProfilePhoneValueFinder() =>
    find.bySemanticsIdentifier('tashil_profile_phone_value');

Future<void> _pumpUntil(
  PatrolIntegrationTester $,
  bool Function() predicate, {
  required Duration deadline,
}) async {
  final end = DateTime.now().add(deadline);
  while (DateTime.now().isBefore(end)) {
    await $.tester.pump(smokePostLoginPumpStep);
    if (predicate()) return;
  }
  expect(predicate(), isTrue, reason: 'Patrol smoke deadline elapsed');
}

Future<void> dismissIosSavePasswordIfVisible(PatrolIntegrationTester $) async {
  for (final label in ['Not Now', 'ليس الآن', 'Never', 'أبداً']) {
    final button = find.text(label);
    if (button.evaluate().isNotEmpty) {
      await $.tester.tap(button);
      await $.tester.pump(smokePostLoginPumpStep);
      return;
    }
  }
}

/// Fills phone + secret on the dev login screen and submits.
Future<void> submitDevDummyLogin(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  expect(creds.hasSecret, isTrue, reason: 'Set PATROL_DEV_SECRET via dart-define');

  await waitForDevLoginScreenAfterSplash($);

  await $(devLoginPhoneLabelFinder()).waitUntilVisible(
    timeout: smokeLoginFieldTimeout,
  );
  await $(devLoginSecretLabelFinder()).waitUntilVisible(
    timeout: smokeLoginFieldTimeout,
  );

  final fields = find.byType(TextFormField);
  expect(fields, findsAtLeastNWidgets(2));

  await $.tester.tap(fields.at(0));
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(fields.at(0), creds.phone);
  await $.tester.pump(smokePostLoginPumpStep);

  await $.tester.tap(fields.at(1));
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(fields.at(1), creds.secret);
  await $.tester.pump(smokePostLoginPumpStep);

  final submit = devLoginSubmitSemanticsFinder();
  if ($.tester.any(submit)) {
    await $.tester.tap(submit);
  } else {
    await $.tester.testTextInput.receiveAction(TextInputAction.done);
  }
  await $.tester.pump(smokePostLoginPumpStep);

  await dismissIosSavePasswordIfVisible($);

  await _pumpUntil(
    $,
    () => $.tester.any(devMainMenuButtonFinder()),
    deadline: smokePostLoginDeadline,
  );
  await $(devMainMenuButtonFinder()).waitUntilVisible(
    timeout: smokeLoginFieldTimeout,
  );
}

/// Opens profile from the main menu and asserts phone + role badge text.
Future<void> verifyDevLoggedInRole(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  await $(devMainMenuButtonFinder()).tap();
  await $.tester.pump(smokePostLoginPumpStep);

  final profileEntry = find.text('الملف الشخصي');
  await $(profileEntry).waitUntilVisible(timeout: smokeLoginFieldTimeout);
  await $.tester.tap(profileEntry);
  await $.tester.pump(smokePostLoginPumpStep);

  await _pumpUntil(
    $,
    () =>
        $.tester.any(devProfilePhoneValueFinder()) ||
        $.tester.any(find.text(creds.phone)),
    deadline: smokePostLoginDeadline,
  );

  if ($.tester.any(devProfilePhoneValueFinder())) {
    await $(devProfilePhoneValueFinder()).waitUntilVisible(
      timeout: smokeLoginFieldTimeout,
    );
  }
  expect(find.textContaining(creds.phone), findsWidgets);
  expect(find.text(creds.expectedRoleLabel), findsOneWidget);
}
