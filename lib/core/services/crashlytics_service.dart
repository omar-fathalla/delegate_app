import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/app_env.dart';

/// خدمة مركزية لإدارة Crashlytics وتسجيل الأخطاء
class CrashlyticsService {
  CrashlyticsService._();

  /// Crashlytics is fully off outside prod (Mohamed's decision for dev):
  /// no collection, no error hooks, no uploads to tashil-dev or production.
  static const bool enabledForEnv = !kIsWeb && AppEnv.name == 'prod';

  static FirebaseCrashlytics? get _crashlytics =>
      enabledForEnv ? FirebaseCrashlytics.instance : null;

  /// تهيئة Crashlytics - يتم استدعاؤها في main()
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!enabledForEnv) {
      // dev: switch native collection off explicitly (Android has no
      // Info.plist flag) and do not install any error handler.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      return;
    }
    // تعطيل في وضع التطوير
    await _crashlytics?.setCrashlyticsCollectionEnabled(!kDebugMode);

    // التقاط أخطاء Flutter framework
    FlutterError.onError = (errorDetails) {
      // Do not use recordFlutterFatalError, as it forcefully crashes the app
      // for ANY layout exception (e.g. bottom overflow by 2 pixels).
      FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      FlutterError.presentError(errorDetails);
    };

    // التقاط أخطاء Dart غير المعالجة (async errors)
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Unhandled Exception: $error');
      debugPrintStack(stackTrace: stack);
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      // Return false to allow the framework to handle the error
      // (e.g., show the ErrorWidget) and prevent infinite render loops.
      return false;
    };
  }

  /// تسجيل خطأ غير حرج (non-fatal)
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (kIsWeb) return;
    await _crashlytics?.recordError(
      exception,
      stack,
      reason: reason ?? 'Non-fatal error',
      fatal: fatal,
    );
  }

  /// تسجيل رسالة مخصصة (breadcrumb)
  static Future<void> log(String message) async {
    if (kIsWeb) return;
    await _crashlytics?.log(message);
  }

  /// تعيين معرف المستخدم للتتبع
  static Future<void> setUserIdentifier(String userId) async {
    if (kIsWeb) return;
    await _crashlytics?.setUserIdentifier(userId);
  }

  /// إضافة مفتاح مخصص للتتبع
  static Future<void> setCustomKey(String key, Object value) async {
    if (kIsWeb) return;
    await _crashlytics?.setCustomKey(key, value);
  }

  /// مسح معرف المستخدم عند تسجيل الخروج
  static Future<void> clearUserIdentifier() async {
    if (kIsWeb) return;
    await _crashlytics?.setUserIdentifier('');
  }
}
