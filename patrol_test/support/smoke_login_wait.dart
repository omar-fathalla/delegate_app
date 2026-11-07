import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

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

/// ENV=dev Maestro marker on the login submit button ([login_screen.dart]).
Finder devLoginScreenSemanticsFinder() {
  return find.bySemanticsIdentifier('tashil_login_submit');
}

Finder devLoginPhoneFieldFinder() => find.byType(TextFormField).at(0);

Finder devLoginSecretFieldFinder() => find.byType(TextFormField).at(1);

bool _loginSubmitHitTestable(WidgetTester tester) {
  final elements = devLoginScreenSemanticsFinder().evaluate();
  for (final element in elements) {
    final render = element.renderObject;
    if (render == null || !render.attached) continue;
    if (render is! RenderBox || !render.hasSize) continue;
    if (render.size.isEmpty) continue;
    return true;
  }
  return false;
}

bool _textFormFieldsHitTestable(WidgetTester tester) {
  final fields = find.byType(TextFormField);
  if (fields.evaluate().length < 2) return false;
  for (final index in [0, 1]) {
    final hitTestable = fields.at(index).hitTestable(at: Alignment.center);
    if (hitTestable.evaluate().isEmpty) return false;
  }
  return true;
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

/// Scrolls the dev login form into view and waits for both [TextFormField]s.
Future<void> waitForDevLoginFormFieldsReady(PatrolIntegrationTester $) async {
  final submit = devLoginScreenSemanticsFinder();
  if ($.tester.any(submit)) {
    await $(submit).scrollTo();
  }

  await settleDevLoginScreenEntrance($);

  final deadline = DateTime.now().add(smokeLoginVisibleTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (_textFormFieldsHitTestable($.tester)) return;

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
  await $(devLoginSecretFieldFinder()).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
    alignment: Alignment.topCenter,
  );
}

/// Waits for splash / auto-login to finish, taps [splash_sign_in] when the stall UI
/// appears, then asserts the dev delegate login screen is visible via [tashil_login_submit].
Future<void> waitForDevLoginScreenAfterSplash(PatrolIntegrationTester $) async {
  final splashSignIn = find.byKey(const Key('splash_sign_in'));
  final deadline = DateTime.now().add(smokeReachLoginDeadline);

  while (DateTime.now().isBefore(deadline)) {
    await $.tester.pump(smokeSplashPollInterval);
    if (_loginSubmitHitTestable($.tester)) {
      await waitForDevLoginFormFieldsReady($);
      return;
    }

    if (splashSignIn.evaluate().isNotEmpty) {
      await $.tester.tap(splashSignIn);
      for (var i = 0; i < smokePostSignInPumpIterations; i++) {
        await $.tester.pump(smokePostSignInPumpStep);
        if (_loginSubmitHitTestable($.tester)) {
          await waitForDevLoginFormFieldsReady($);
          return;
        }
      }
    }
  }

  await $(devLoginScreenSemanticsFinder()).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
  );
  await waitForDevLoginFormFieldsReady($);
}
