import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/maps_keys.dart';
import 'package:delegate_app/firebase_options.dart' as prod;
import 'package:delegate_app/firebase_options_dev.dart' as dev;

/// Build environment, chosen at compile time with `--dart-define=ENV=dev`.
///
/// Defaults to `prod`, so builds without the define are unchanged.
/// `ENV=dev` always uses the tashil-dev Firebase project and never falls back
/// to production. Any other value fails at startup.
///
/// ENV=dev is web-only for now. Android still bundles the production
/// google-services.json (no `dev` flavor yet) and there is no dev iOS app, so
/// a dev build on those platforms fails closed instead of mixing projects.
class AppEnv {
  AppEnv._();

  static const String name = String.fromEnvironment(
    'ENV',
    defaultValue: 'prod',
  );

  static const bool isDev = name == 'dev';

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
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      throw UnsupportedError(
        'ENV=dev is not supported on ${platform.name} yet: there is no dev '
        'flavor/app, so it would mix tashil-dev with production config. '
        'Use ENV=dev on web only.',
      );
    }
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

  static String mapsJsApiKeyFor(String env, [String override = '']) {
    if (override.isNotEmpty) return override;
    return env == 'dev' ? MapsKeys.devMapsPlaces : MapsKeys.prodMapsJs;
  }

  static String placesApiKeyFor(String env, [String override = '']) {
    if (override.isNotEmpty) return override;
    return env == 'dev' ? MapsKeys.devMapsPlaces : MapsKeys.prodPlaces;
  }
}
