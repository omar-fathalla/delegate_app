import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Forced-update gate (TAS-66).
///
/// Old builds sign in anonymously and lose every Firestore read once the
/// `dev-latest` rules are published. The gate lets us tell those users to
/// update instead of leaving them with a silently broken app.
///
/// Source: Firebase Remote Config, read before any login, so it needs no
/// Firestore rule and works for anonymous and signed-out users:
/// - `min_app_version_android`, `min_app_version_ios`: lowest allowed
///   version, e.g. `1.15.0` or `1.15.0+120`. Empty = no gate.
/// - `store_url_android`, `store_url_ios`: where the update button goes.
///   Empty = the built-in store page for the production bundle id.
///
/// Fail-open: offline, timeout, missing Firebase app or an unparsable value
/// all leave the app usable. The gate only blocks when a fetched minimum is
/// higher than the running version. Web (HR/admin console) is never gated.
///
/// [refresh] is started once after `Firebase.initializeApp`; the splash
/// screen awaits [ready] (with its own timeout) before the auto-login.
abstract final class AppVersionGate {
  static const String minVersionAndroidKey = 'min_app_version_android';
  static const String minVersionIosKey = 'min_app_version_ios';
  static const String storeUrlAndroidKey = 'store_url_android';
  static const String storeUrlIosKey = 'store_url_ios';

  /// `/update-required` route; also the redirect target while blocked.
  static const String routePath = '/update-required';

  static const String defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.tashil.delegate';

  static const Duration fetchTimeout = Duration(seconds: 10);
  static const Duration activateTimeout = Duration(seconds: 12);
  static const Duration debugMinimumFetchInterval = Duration.zero;
  static const Duration releaseMinimumFetchInterval = Duration(hours: 1);

  /// How long the splash screen waits for a decision before continuing.
  static const Duration splashWait = Duration(seconds: 4);

  /// Current decision. Listened to by the router (`refreshListenable`).
  static final ValueNotifier<AppVersionGateDecision> decision =
      ValueNotifier<AppVersionGateDecision>(AppVersionGateDecision.allowed);

  static bool get isBlocked => decision.value.updateRequired;

  static Completer<void>? _refreshing;

  /// Completes when the current [refresh] finishes (or at once when none
  /// was started). Never fails.
  static Future<void> get ready =>
      _refreshing?.future ?? Future<void>.value();

  /// Fetches Remote Config, compares it with the running version and
  /// publishes the decision on [decision]. Never throws.
  static Future<void> refresh({
    AppVersionGateSource? source,
    String? currentVersion,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
    Duration timeout = activateTimeout,
  }) async {
    final completer = Completer<void>();
    _refreshing = completer;
    try {
      if (isWeb) {
        decision.value = AppVersionGateDecision.allowed;
        return;
      }
      final gateSource =
          source ?? FirebaseAppVersionGateSource(FirebaseRemoteConfig.instance);
      await gateSource.prepare().timeout(timeout);
      final values = gateSource.read();
      final version =
          currentVersion ?? (await PackageInfo.fromPlatform()).version;
      final result = evaluate(
        values: values,
        currentVersion: version,
        platform: platform ?? defaultTargetPlatform,
      );
      debugPrint(
        'app_version_gate current=$version min=${result.minVersion} '
        'required=${result.updateRequired}',
      );
      decision.value = result;
    } catch (error) {
      debugPrint('app_version_gate unavailable, allowing ($error)');
      decision.value = AppVersionGateDecision.allowed;
    } finally {
      completer.complete();
    }
  }

  /// Pure decision: blocks only when [values] carry a parsable minimum for
  /// [platform] that is higher than [currentVersion].
  static AppVersionGateDecision evaluate({
    required AppVersionGateValues values,
    required String currentVersion,
    required TargetPlatform platform,
  }) {
    final isIos = platform == TargetPlatform.iOS;
    final minVersion = (isIos ? values.minVersionIos : values.minVersionAndroid)
        .trim();
    if (minVersion.isEmpty) return AppVersionGateDecision.allowed;
    if (parseVersion(minVersion) == null || parseVersion(currentVersion) == null) {
      return AppVersionGateDecision.allowed;
    }
    final storeUrl = (isIos ? values.storeUrlIos : values.storeUrlAndroid).trim();
    return AppVersionGateDecision(
      updateRequired: compareVersions(currentVersion, minVersion) < 0,
      currentVersion: currentVersion,
      minVersion: minVersion,
      storeUrl: storeUrl.isNotEmpty
          ? storeUrl
          : (isIos ? '' : defaultPlayStoreUrl),
    );
  }

  /// Clears the decision and any pending refresh (tests only).
  @visibleForTesting
  static void debugReset() {
    decision.value = AppVersionGateDecision.allowed;
    _refreshing = null;
  }
}

/// Numeric parts of `major.minor.patch[+build]`; `null` when any part is not
/// a number. `1.2` reads as `[1, 2]`, `1.2.3+45` as `[1, 2, 3, 45]`.
List<int>? parseVersion(String version) {
  final text = version.trim();
  if (text.isEmpty) return null;
  final parts = text.replaceFirst('+', '.').split('.');
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part.trim());
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  return numbers;
}

/// Negative when [a] < [b], zero when equal, positive when [a] > [b].
/// Missing trailing parts count as 0, so `1.15` equals `1.15.0`.
/// Unparsable input compares as equal (the caller treats that as "allowed").
int compareVersions(String a, String b) {
  final pa = parseVersion(a);
  final pb = parseVersion(b);
  if (pa == null || pb == null) return 0;
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

@immutable
class AppVersionGateValues {
  const AppVersionGateValues({
    this.minVersionAndroid = '',
    this.minVersionIos = '',
    this.storeUrlAndroid = '',
    this.storeUrlIos = '',
  });

  final String minVersionAndroid;
  final String minVersionIos;
  final String storeUrlAndroid;
  final String storeUrlIos;
}

@immutable
class AppVersionGateDecision {
  const AppVersionGateDecision({
    required this.updateRequired,
    required this.currentVersion,
    required this.minVersion,
    required this.storeUrl,
  });

  static const AppVersionGateDecision allowed = AppVersionGateDecision(
    updateRequired: false,
    currentVersion: '',
    minVersion: '',
    storeUrl: '',
  );

  final bool updateRequired;
  final String currentVersion;
  final String minVersion;

  /// Empty when no store link is known (iOS without `store_url_ios`).
  final String storeUrl;

  @override
  bool operator ==(Object other) =>
      other is AppVersionGateDecision &&
      other.updateRequired == updateRequired &&
      other.currentVersion == currentVersion &&
      other.minVersion == minVersion &&
      other.storeUrl == storeUrl;

  @override
  int get hashCode =>
      Object.hash(updateRequired, currentVersion, minVersion, storeUrl);
}

/// Reads the gate keys without this library calling Firebase in tests.
abstract interface class AppVersionGateSource {
  Future<void> prepare();
  AppVersionGateValues read();
}

/// Production source. Constructed only after `Firebase.initializeApp`.
/// It shares the Remote Config instance with `DelegateOtpConfig`; both set
/// the same settings and `fetchAndActivate` is cached by the SDK, so the
/// order they run in does not matter.
final class FirebaseAppVersionGateSource implements AppVersionGateSource {
  FirebaseAppVersionGateSource(this._remote);

  final FirebaseRemoteConfig _remote;

  @override
  Future<void> prepare() async {
    await _remote.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: AppVersionGate.fetchTimeout,
        minimumFetchInterval: kDebugMode
            ? AppVersionGate.debugMinimumFetchInterval
            : AppVersionGate.releaseMinimumFetchInterval,
      ),
    );
    await _remote.fetchAndActivate();
  }

  @override
  AppVersionGateValues read() => AppVersionGateValues(
        minVersionAndroid: _remote.getString(AppVersionGate.minVersionAndroidKey),
        minVersionIos: _remote.getString(AppVersionGate.minVersionIosKey),
        storeUrlAndroid: _remote.getString(AppVersionGate.storeUrlAndroidKey),
        storeUrlIos: _remote.getString(AppVersionGate.storeUrlIosKey),
      );
}
