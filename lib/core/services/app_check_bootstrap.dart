import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';

/// TAS-16 step 1: Firebase App Check in monitoring mode only.
///
/// Nothing is enforced: Firestore / Functions / Storage keep accepting
/// requests without a valid token until enforcement is switched on in the
/// Firebase console. Until then the console only reports verified vs
/// unverified traffic.
///
/// Providers:
/// - Android release on prod: Play Integrity.
/// - iOS release on prod: DeviceCheck (not App Attest, which needs a new
///   entitlement and provisioning profile).
/// - Dev (ENV=dev, the `dev` flavor) or any non-release build: the debug
///   provider. Its token is printed to logcat / the Xcode console and must be
///   registered under App Check > Manage debug tokens on tashil-dev.
///
/// Must never block or crash startup: the call is fire-and-forget, and any
/// error is swallowed and reported as a non-fatal (prod only).
void activateAppCheckMonitoring() {
  // TODO(TAS-16): HR web needs a reCAPTCHA Enterprise site key before it can
  // activate App Check (providerWeb). Skipped on web until then.
  if (kIsWeb) return;
  unawaited(_activate());
}

@visibleForTesting
bool appCheckUsesDebugProvider({
  bool isDev = AppEnv.isDev,
  bool releaseMode = kReleaseMode,
}) => isDev || !releaseMode;

Future<void> _activate() async {
  try {
    final debug = appCheckUsesDebugProvider();
    await FirebaseAppCheck.instance.activate(
      providerAndroid: debug
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: debug
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    );
    debugPrint('App Check activated (monitoring, debug provider: $debug)');
  } catch (e, st) {
    // Only the error type: never a token or user data in the log.
    debugPrint('App Check activation skipped: ${e.runtimeType}');
    unawaited(
      CrashlyticsService.recordError(
        e,
        st,
        reason: 'TAS-16 App Check activation failed (monitoring only)',
      ).catchError((Object _) {}),
    );
  }
}
