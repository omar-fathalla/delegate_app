import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

/// Poll interval while splash / auto-login may still be in flight.
const Duration smokeSplashPollInterval = Duration(milliseconds: 500);

/// Wall-clock budget to reach the delegate login screen (stall path ~12s + nav).
const Duration smokeReachLoginDeadline = Duration(seconds: 60);

/// Final visibility wait after the bootstrap loop.
const Duration smokeLoginVisibleTimeout = Duration(seconds: 30);

/// Post–sign-in navigation pumps (avoid [pumpAndSettle] on live Firebase streams).
const Duration smokePostSignInPumpStep = Duration(milliseconds: 200);

const int smokePostSignInPumpIterations = 40;

/// ENV=dev Maestro marker on the login submit button ([login_screen.dart]).
Finder devLoginScreenSemanticsFinder() {
  return find.bySemanticsIdentifier('tashil_login_submit');
}

/// Phone field leading icon — present on mobile [LoginScreen], not on splash stall UI.
Finder devLoginPhoneFieldIconFinder() {
  return find.byIcon(Icons.phone_android_rounded);
}

bool _loginScreenHitTestable(WidgetTester tester) {
  for (final finder in [
    devLoginScreenSemanticsFinder(),
    devLoginPhoneFieldIconFinder(),
  ]) {
    final elements = finder.evaluate();
    for (final element in elements) {
      final render = element.renderObject;
      if (render == null || !render.attached) continue;
      if (render is! RenderBox || !render.hasSize) continue;
      if (render.size.isEmpty) continue;
      return true;
    }
  }
  return false;
}

/// Waits for splash / auto-login to finish, taps [splash_sign_in] when the stall UI
/// appears, then asserts the dev delegate login screen is visible.
Future<void> waitForDevLoginScreenAfterSplash(PatrolIntegrationTester $) async {
  final splashSignIn = find.byKey(const Key('splash_sign_in'));
  final deadline = DateTime.now().add(smokeReachLoginDeadline);

  while (DateTime.now().isBefore(deadline)) {
    await $.tester.pump(smokeSplashPollInterval);
    if (_loginScreenHitTestable($.tester)) return;

    if (splashSignIn.evaluate().isNotEmpty) {
      await $.tester.tap(splashSignIn);
      for (var i = 0; i < smokePostSignInPumpIterations; i++) {
        await $.tester.pump(smokePostSignInPumpStep);
        if (_loginScreenHitTestable($.tester)) return;
      }
    }
  }

  final semantics = $(devLoginScreenSemanticsFinder());
  if (semantics.exists) {
    await semantics.waitUntilVisible(timeout: smokeLoginVisibleTimeout);
    return;
  }

  await $(devLoginPhoneFieldIconFinder()).waitUntilVisible(
    timeout: smokeLoginVisibleTimeout,
  );
}
