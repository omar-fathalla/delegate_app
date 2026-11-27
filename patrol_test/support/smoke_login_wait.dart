import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'smoke_login_finders.dart';

/// Poll interval while splash / auto-login may still be in flight.
const Duration smokeSplashPollInterval = Duration(milliseconds: 500);

/// Wall-clock budget to reach the delegate login screen (stall path ~12s + nav).
const Duration smokeReachLoginDeadline = Duration(seconds: 60);

/// Final visibility wait after the bootstrap loop.
const Duration smokeLoginVisibleTimeout = Duration(seconds: 30);

/// Matches [LoginScreen] entrance animation (~extraLong4 / 1000ms) plus layout.
const Duration smokeLoginEntranceAnimation = Duration(milliseconds: 1100);

/// Post–sign-in navigation pumps (avoid [pumpAndSettle] on live Firebase streams).
const Duration smokePostSignInPumpStep = Duration(milliseconds: 200);

const int smokePostSignInPumpIterations = 40;

/// Which credential fields are visible for the active M3 login mode segment.
enum SmokeDevLoginFieldMode {
  /// Default [LoginScreen] segment (**مندوب**): phone + national ID.
  delegate,

  /// **موظف إداري** segment: phone + staff password.
  staff,
}

/// ValueKeys waited on per mode (Patrol smoke contract; unit-tested).
List<String> smokeDevLoginFieldValueKeys(SmokeDevLoginFieldMode mode) {
  switch (mode) {
    case SmokeDevLoginFieldMode.delegate:
      return const ['login_phone', 'login_national_id'];
    case SmokeDevLoginFieldMode.staff:
      return const ['login_phone', 'login_staff_password'];
  }
}

bool _loginSubmitHitTestable(WidgetTester tester) {
  final hitTestable =
      devLoginSubmitFinder().hitTestable(at: Alignment.center);
  return hitTestable.evaluate().isNotEmpty;
}

bool _delegateLoginFieldsHitTestable(WidgetTester tester) {
  final phone =
      devLoginPhoneFieldFinder().hitTestable(at: Alignment.center);
  final nationalId =
      devLoginDelegateNationalIdFieldFinder().hitTestable(at: Alignment.center);
  return phone.evaluate().isNotEmpty && nationalId.evaluate().isNotEmpty;
}

bool _staffLoginFieldsHitTestable(WidgetTester tester) {
  final phone =
      devLoginPhoneFieldFinder().hitTestable(at: Alignment.center);
  final secret =
      devLoginStaffPasswordFieldFinder().hitTestable(at: Alignment.center);
  return phone.evaluate().isNotEmpty && secret.evaluate().isNotEmpty;
}

bool _loginFieldsHitTestable(
  WidgetTester tester,
  SmokeDevLoginFieldMode mode,
) {
  switch (mode) {
    case SmokeDevLoginFieldMode.delegate:
      return _delegateLoginFieldsHitTestable(tester);
    case SmokeDevLoginFieldMode.staff:
      return _staffLoginFieldsHitTestable(tester);
  }
}

Finder _secondaryFieldFinder(SmokeDevLoginFieldMode mode) {
  switch (mode) {
    case SmokeDevLoginFieldMode.delegate:
      return devLoginDelegateNationalIdFieldFinder();
    case SmokeDevLoginFieldMode.staff:
      return devLoginStaffPasswordFieldFinder();
  }
}

/// Pumps through the login screen slide/fade so fields are hit-testable.
Future<void> settleDevLoginScreenEntrance(PatrolIntegrationTester $) async {
  final steps =
      smokeLoginEntranceAnimation.inMilliseconds ~/
      smokeSplashPollInterval.inMilliseconds;
  for (var i = 0; i < steps; i++) {
    await $.tester.pump(smokeSplashPollInterval);
  }
}

/// Scrolls the dev login form into view and waits for mode-appropriate fields.
///
/// Default is [SmokeDevLoginFieldMode.delegate] (**مندوب**). For staff flows,
/// tap **موظف إداري** first, then call again with [SmokeDevLoginFieldMode.staff].
Future<void> waitForDevLoginFormFieldsReady(
  PatrolIntegrationTester $, {
  SmokeDevLoginFieldMode mode = SmokeDevLoginFieldMode.delegate,
}) async {
  final submit = devLoginSubmitFinder();
  if ($.tester.any(submit)) {
    await $(submit).scrollTo();
  }

  await settleDevLoginScreenEntrance($);

  final secondaryFinder = _secondaryFieldFinder(mode);
  final deadline = DateTime.now().add(smokeLoginVisibleTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (_loginFieldsHitTestable($.tester, mode)) return;

    if ($.tester.any(submit)) {
      await $(submit).scrollTo();
    }
    await $(devLoginPhoneFieldFinder()).scrollTo(
      alignment: Alignment.topCenter,
    );
    await $.tester.pump(smokeSplashPollInterval);
  }

  await $(devLoginPhoneFieldFinder()).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
    alignment: Alignment.topCenter,
  );
  await $(secondaryFinder).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
    alignment: Alignment.topCenter,
  );
}

/// Taps **موظف إداري** / [LoginMode.staff] then waits for staff credential fields.
Future<void> tapDevLoginStaffModeAndWaitForFields(
  PatrolIntegrationTester $,
) async {
  final staffMode = devLoginStaffModeFinder();
  await $(staffMode).waitUntilVisible(timeout: smokeLoginVisibleTimeout);
  await $.tester.tap(staffMode);
  await $.tester.pump(smokePostSignInPumpStep);
  await waitForDevLoginFormFieldsReady($, mode: SmokeDevLoginFieldMode.staff);
}

/// The login screen remembers the last account type (TAS-393: a second test in
/// the same Patrol file reopens it on **موظف إداري**), so wait for the fields
/// of whichever mode is showing.
SmokeDevLoginFieldMode _visibleLoginMode() =>
    devLoginStaffPasswordFieldFinder().evaluate().isNotEmpty
        ? SmokeDevLoginFieldMode.staff
        : SmokeDevLoginFieldMode.delegate;

/// Waits for splash / auto-login to finish, taps [splash_sign_in] when the stall UI
/// appears, then asserts the dev login screen submit control is visible.
Future<void> waitForDevLoginScreenAfterSplash(PatrolIntegrationTester $) async {
  final splashSignIn = find.byKey(const Key('splash_sign_in'));
  final deadline = DateTime.now().add(smokeReachLoginDeadline);

  while (DateTime.now().isBefore(deadline)) {
    await $.tester.pump(smokeSplashPollInterval);
    if (_loginSubmitHitTestable($.tester)) {
      await waitForDevLoginFormFieldsReady($, mode: _visibleLoginMode());
      return;
    }

    if (splashSignIn.evaluate().isNotEmpty) {
      await $.tester.tap(splashSignIn);
      for (var i = 0; i < smokePostSignInPumpIterations; i++) {
        await $.tester.pump(smokePostSignInPumpStep);
        if (_loginSubmitHitTestable($.tester)) {
          await waitForDevLoginFormFieldsReady($, mode: _visibleLoginMode());
          return;
        }
      }
    }
  }

  await $(devLoginSubmitFinder()).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
  );
  await waitForDevLoginFormFieldsReady($, mode: _visibleLoginMode());
}
