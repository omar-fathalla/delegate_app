import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'patrol_native_actions.dart';
import 'smoke_dev_credentials.dart';
import 'smoke_login_finders.dart';
import 'smoke_login_wait.dart';

const Duration smokeLoginFieldTimeout = Duration(seconds: 45);
const Duration smokePostLoginDeadline = Duration(seconds: 180);
const Duration smokePostLoginPumpStep = Duration(milliseconds: 250);

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

Future<void> awaitDevMainMenuAfterLogin(PatrolIntegrationTester $) async {
  final end = DateTime.now().add(smokePostLoginDeadline);
  var tick = 0;
  var savePasswordDismissPasses = 0;
  const maxSavePasswordDismissPasses = 8;
  while (DateTime.now().isBefore(end)) {
    if (tick % 24 == 0 && savePasswordDismissPasses < maxSavePasswordDismissPasses) {
      await patrolDismissIosSavePasswordSheet($);
      savePasswordDismissPasses++;
    }
    tick++;
    await $.tester.pump(smokePostLoginPumpStep);
    if ($.tester.any(devMainMenuButtonFinder())) {
      await $(devMainMenuButtonFinder()).waitUntilVisible(
        timeout: smokeLoginFieldTimeout,
      );
      return;
    }
  }
  expect(
    $.tester.any(devMainMenuButtonFinder()),
    isTrue,
    reason: 'Patrol login deadline elapsed before main menu',
  );
}

/// Fills phone + secret on the dev login screen and submits.
Future<void> submitDevDummyLogin(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  expect(creds.hasSecret, isTrue, reason: 'Set PATROL_DEV_SECRET via dart-define');

  await waitForDevLoginScreenAfterSplash($);

  await tapDevLoginStaffModeAndWaitForFields($);

  final phoneField = devLoginPhoneFieldFinder();
  final secretField = devLoginStaffPasswordFieldFinder();
  expect(phoneField, findsOneWidget);
  expect(secretField, findsOneWidget);

  await $.tester.tap(phoneField);
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(phoneField, creds.phone);
  await $.tester.pump(smokePostLoginPumpStep);

  await $.tester.tap(secretField);
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(secretField, creds.secret);
  await $.tester.pump(smokePostLoginPumpStep);

  final submit = devLoginSubmitFinder();
  expect($.tester.any(submit), isTrue, reason: 'login_submit must be visible');
  await $(submit).scrollTo();
  await $.tester.tap(submit);
  await $.tester.pump(smokePostLoginPumpStep);

  await patrolDismissIosSavePasswordSheet($);
  await awaitDevMainMenuAfterLogin($);
}

/// Delegate (**مندوب**) login — setup only; no post-login journey assertions.
Future<void> submitDevDelegateDummyLogin(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  expect(
    creds.hasDelegateNationalId,
    isTrue,
    reason: 'Set PATROL_DEV_NATIONAL_ID for delegate Patrol setup',
  );

  await waitForDevLoginScreenAfterSplash($);
  await waitForDevLoginFormFieldsReady($);

  final delegateMode = devLoginDelegateModeFinder();
  if ($.tester.any(delegateMode)) {
    await $.tester.tap(delegateMode);
    await $.tester.pump(smokePostLoginPumpStep);
    await waitForDevLoginFormFieldsReady($);
  }

  final phoneField = devLoginPhoneFieldFinder();
  final nationalIdField = devLoginDelegateNationalIdFieldFinder();
  expect(phoneField, findsOneWidget);
  expect(nationalIdField, findsOneWidget);

  await $.tester.tap(phoneField);
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(phoneField, creds.phone);
  await $.tester.pump(smokePostLoginPumpStep);

  await $.tester.tap(nationalIdField);
  await $.tester.pump(smokePostLoginPumpStep);
  await $.tester.enterText(nationalIdField, creds.nationalId);
  await $.tester.pump(smokePostLoginPumpStep);

  final submit = devLoginSubmitFinder();
  await $(submit).scrollTo();
  await $.tester.tap(submit);
  await $.tester.pump(smokePostLoginPumpStep);

  await patrolDismissIosSavePasswordSheet($);
  await $.tester.pump(const Duration(milliseconds: 800));
  await patrolDismissIosSavePasswordSheet($);
  await awaitDevMainMenuAfterLogin($);
}

/// Maestro-only journey assertion (profile phone + role). Patrol setup must not call this.
Future<void> verifyDevLoggedInRole(
  PatrolIntegrationTester $,
  SmokeDevPatrolCredentials creds,
) async {
  await $(devMainMenuButtonFinder()).tap();
  await $.tester.pump(smokePostLoginPumpStep);

  final profileEntry = find.text('الملف الشخصي');
  await $(profileEntry).scrollTo();
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

  await $(devProfilePhoneValueFinder()).waitUntilVisible(
    timeout: smokeLoginFieldTimeout,
  );
  expect(devProfilePhoneValueFinder(), findsOneWidget);
  expect(find.text(creds.phone), findsWidgets);

  final roleBadge = find.text(creds.expectedRoleLabel);
  await _pumpUntil(
    $,
    () => $.tester.any(roleBadge),
    deadline: smokePostLoginDeadline,
  );
  await $(roleBadge).waitUntilVisible(timeout: smokeLoginFieldTimeout);
  expect(roleBadge, findsOneWidget);
}
