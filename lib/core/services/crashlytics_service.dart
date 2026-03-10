import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// خدمة مركزية لإدارة Crashlytics وتسجيل الأخطاء
class CrashlyticsService {
  CrashlyticsService._();

  static final FirebaseCrashlytics _crashlytics =
      FirebaseCrashlytics.instance;

  /// تهيئة Crashlytics - يتم استدعاؤها في main()
  static Future<void> initialize() async {
    // تعطيل في وضع التطوير
    await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    // التقاط أخطاء Flutter framework
    FlutterError.onError = (errorDetails) {
      _crashlytics.recordFlutterFatalError(errorDetails);
    };

    // التقاط أخطاء Dart غير المعالجة (async errors)
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// تسجيل خطأ غير حرج (non-fatal)
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    await _crashlytics.recordError(
      exception,
      stack,
      reason: reason ?? 'Non-fatal error',
      fatal: fatal,
    );
  }

  /// تسجيل رسالة مخصصة (breadcrumb)
  static Future<void> log(String message) async {
    await _crashlytics.log(message);
  }

  /// تعيين معرف المستخدم للتتبع
  static Future<void> setUserIdentifier(String userId) async {
    await _crashlytics.setUserIdentifier(userId);
  }

  /// إضافة مفتاح مخصص للتتبع
  static Future<void> setCustomKey(String key, Object value) async {
    await _crashlytics.setCustomKey(key, value);
  }

  /// مسح معرف المستخدم عند تسجيل الخروج
  static Future<void> clearUserIdentifier() async {
    await _crashlytics.setUserIdentifier('');
  }
}
