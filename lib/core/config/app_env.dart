import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/maps_keys.dart';
import 'package:delegate_app/firebase_options.dart' as prod;
import 'package:delegate_app/firebase_options_dev.dart' as dev;

/// Build environment, chosen at compile time with `--dart-define=ENV=dev`.
///
/// Defaults to `dev` (TAS-78): a build or run without the define talks to
/// tashil-dev, never to production. Store builds must pass
/// `--dart-define=ENV=prod` (android-release.yml and deploy-ios.yml do).
/// `ENV=dev` always uses the tashil-dev Firebase project and never falls back
/// to production. Any other value fails at startup.
///
/// ENV=dev works on web, on Android with the `dev` flavor
/// (`flutter build apk --flavor dev --dart-define=ENV=dev`) and on iOS with the
/// `dev` flavor (`flutter build ios --flavor dev --dart-define=ENV=dev`). Both
/// mobile flavors use the tashil-dev apps registered for com.tashil.delegate.dev.
/// On iOS dev the native side never calls FirebaseApp.configure(); Firebase is
/// initialised from Dart with these options only. Other platforms fail closed.
class AppEnv {
  AppEnv._();

  static const String name = String.fromEnvironment(
    'ENV',
    defaultValue: 'dev',
  );

  static const bool isDev = name == 'dev';

  /// Compile-time git SHA from `--dart-define=GIT_SHA=<full sha>`.
  /// Empty when the define was not passed. Dev builds show this on the
  /// login screen and log `GIT_SHA=<sha>` at startup so User Test can
  /// verify the installed artifact. Production UI never displays it.
  static const String gitSha = String.fromEnvironment('GIT_SHA');

  static const String devProjectId = 'tashil-dev';
  static const String prodProjectId = 'practice-firebase-72df1';

  /// Firebase project this build must talk to.
  static const String expectedProjectId = isDev ? devProjectId : prodProjectId;

  /// Call after Firebase.initializeApp: fails closed if the default app is not
  /// the project this build was compiled for (e.g. a dev build that somehow
  /// got the production config from a native plist).
  static void verifyFirebaseProject(String actualProjectId) =>
      verifyFirebaseProjectFor(name, actualProjectId);

  @visibleForTesting
  static void verifyFirebaseProjectFor(String env, String actualProjectId) {
    final expected = env == 'dev' ? devProjectId : prodProjectId;
    if (actualProjectId != expected) {
      throw StateError(
        'ENV=$env expects Firebase project "$expected" but the app is '
        'configured for "$actualProjectId". Refusing to continue.',
      );
    }
  }

  /// Firebase options for the current environment.
  ///
  /// Branches on compile-time constants so a release build only contains the
  /// config for its own environment.
  static FirebaseOptions get firebaseOptions {
    if (isDev) {
      ensureDevSupported(isWeb: kIsWeb, platform: defaultTargetPlatform);
      return dev.DefaultFirebaseOptions.currentPlatform;
    }
    if (name == 'prod') return prod.DefaultFirebaseOptions.currentPlatform;
    throw UnsupportedError('Unknown ENV "$name". Use prod or dev.');
  }

  /// Throws when ENV=dev runs on a platform with no dev Firebase setup.
  static void ensureDevSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return;
    if (platform == TargetPlatform.android) return;
    if (platform == TargetPlatform.iOS) return;
    throw UnsupportedError(
      'ENV=dev is not supported on ${platform.name}: there is no tashil-dev '
      'app for it. Use ENV=dev on web, Android or iOS (--flavor dev).',
    );
  }

  /// Same mapping as [firebaseOptions] for an explicit [env] (used in tests).
  static FirebaseOptions optionsFor(
    String env, {
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) {
    switch (env) {
      case 'prod':
        return prod.DefaultFirebaseOptions.currentPlatform;
      case 'dev':
        ensureDevSupported(
          isWeb: isWeb,
          platform: platform ?? defaultTargetPlatform,
        );
        return dev.DefaultFirebaseOptions.currentPlatform;
      default:
        throw UnsupportedError('Unknown ENV "$env". Use prod or dev.');
    }
  }

  /// Optional override: `--dart-define=MAPS_API_KEY=...`.
  static const String _mapsKeyOverride = String.fromEnvironment('MAPS_API_KEY');

  /// Maps JavaScript key for the current environment. Branches on
  /// compile-time constants so a release build only contains its own key.
  static String get mapsJsApiKey {
    if (_mapsKeyOverride.isNotEmpty) return _mapsKeyOverride;
    if (isDev) return MapsKeys.devMapsPlaces;
    return MapsKeys.prodMapsJs;
  }

  /// Places key for the current environment (same const branching).
  static String get placesApiKey {
    if (_mapsKeyOverride.isNotEmpty) return _mapsKeyOverride;
    if (isDev) return MapsKeys.devMapsPlaces;
    return MapsKeys.prodPlaces;
  }

  /// Test helpers mirroring the getters for an arbitrary env name.

  @visibleForTesting
  static String mapsJsApiKeyFor(String env, [String override = '']) {
    if (override.isNotEmpty) return override;
    return env == 'dev' ? MapsKeys.devMapsPlaces : MapsKeys.prodMapsJs;
  }

  @visibleForTesting
  static String placesApiKeyFor(String env, [String override = '']) {
    if (override.isNotEmpty) return override;
    return env == 'dev' ? MapsKeys.devMapsPlaces : MapsKeys.prodPlaces;
  }
}
