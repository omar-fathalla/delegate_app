import 'package:flutter/foundation.dart';

/// Web-only decisions for staff and delegate flows.
///
/// [debugIsWebOverride] lets tests simulate a browser without a web compile.
/// Mobile builds leave it null, so [isWeb] stays [kIsWeb] and behavior is
/// unchanged.
class WebRuntimePolicy {
  WebRuntimePolicy._();

  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get isWeb => debugIsWebOverride ?? kIsWeb;

  /// The login screen keeps مندوب / موظف إداري on web and on mobile.
  static const bool loginKeepsModeTabs = true;

  /// Device binding writes and mismatch checks are app-only.
  static bool get delegateDeviceBindingEnabled => !isWeb;

  /// Check-in asks for location and is app-only.
  static bool get checkInEnabled => !isWeb;

  /// Background live tracking asks for location and is app-only.
  static bool get liveTrackingEnabled => !isWeb;

  /// FCM token registration and permission prompts are app-only.
  static bool get pushNotificationsEnabled => !isWeb;

  static const String delegateLoginWebMessage =
      'تسجيل دخول المندوب وربط الجهاز متاح من تطبيق الجوال فقط.';

  static const String delegateLoginWebMessageEn =
      'Delegate sign-in and device binding are only available in the mobile app.';

  static const String checkInWebMessage =
      'تسجيل الحضور والانصراف متاح من تطبيق الجوال فقط.';

  static const String trackingWebMessage =
      'التتبع المباشر متاح من تطبيق الجوال فقط.';

  /// Web must not build `companies/{empty}` document paths.
  static bool skipEmptyCompanyDelegateDirectory({required String companyUID}) =>
      isWeb && companyUID.trim().isEmpty;

  @visibleForTesting
  static void debugReset() => debugIsWebOverride = null;
}
