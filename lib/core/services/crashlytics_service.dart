import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/app_env.dart';

import 'crashlytics_ops.dart' deferred as crashlytics_ops;

/// خدمة مركزية لإدارة Crashlytics وتسجيل الأخطاء
class CrashlyticsService {
  CrashlyticsService._();

  /// Crashlytics is fully off outside prod (Mohamed's decision for dev):
  /// no collection, no error hooks, no uploads to tashil-dev or production.
  /// The implementation library is [deferred] and only loaded after
  /// [ensureLoaded] in prod so dev never instantiates Firebase Crashlytics APIs.
  static const bool enabledForEnv = !kIsWeb && AppEnv.name == 'prod';

  static Future<void>? _loadLibrary;

  static Future<void> ensureLoaded() {
    if (kIsWeb || !enabledForEnv) {
      return Future<void>.value();
    }
    _loadLibrary ??= crashlytics_ops.loadLibrary();
    return _loadLibrary!;
  }

  /// تهيئة Crashlytics - يتم استدعاؤها في main()
  static Future<void> initialize() async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.initializeCrashlyticsOps();
  }

  /// تسجيل خطأ غير حرج (non-fatal)
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.recordErrorOps(
      exception,
      stack,
      reason: reason ?? 'Non-fatal error',
      fatal: fatal,
    );
  }

  /// تسجيل رسالة مخصصة (breadcrumb)
  static Future<void> log(String message) async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.logOps(message);
  }

  /// تعيين معرف المستخدم للتتبع
  static Future<void> setUserIdentifier(String userId) async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.setUserIdentifierOps(userId);
  }

  /// إضافة مفتاح مخصص للتتبع
  static Future<void> setCustomKey(String key, Object value) async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.setCustomKeyOps(key, value);
  }

  /// مسح معرف المستخدم عند تسجيل الخروج
  static Future<void> clearUserIdentifier() async {
    if (kIsWeb || !enabledForEnv) return;
    await ensureLoaded();
    await crashlytics_ops.setUserIdentifierOps('');
  }
}
