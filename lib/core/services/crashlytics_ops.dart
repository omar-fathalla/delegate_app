import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics implementation loaded only via [deferred import] from
/// [CrashlyticsService] when `AppEnv.name == 'prod'`, so dev builds never
/// load this library and never touch [FirebaseCrashlytics].
Future<void> initializeCrashlyticsOps() async {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (FlutterErrorDetails errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
    FlutterError.presentError(errorDetails);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Unhandled Exception: $error');
    debugPrintStack(stackTrace: stack);
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    return false;
  };
}

Future<void> recordErrorOps(
  dynamic exception,
  StackTrace? stack, {
  required String reason,
  required bool fatal,
}) async {
  await FirebaseCrashlytics.instance.recordError(
    exception,
    stack,
    reason: reason,
    fatal: fatal,
  );
}

Future<void> logOps(String message) async {
  await FirebaseCrashlytics.instance.log(message);
}

Future<void> setUserIdentifierOps(String userId) async {
  await FirebaseCrashlytics.instance.setUserIdentifier(userId);
}

Future<void> setCustomKeyOps(String key, Object value) async {
  await FirebaseCrashlytics.instance.setCustomKey(key, value);
}
