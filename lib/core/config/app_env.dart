import 'package:firebase_core/firebase_core.dart';

import 'package:delegate_app/firebase_options.dart' as prod;
import 'package:delegate_app/firebase_options_dev.dart' as dev;

/// Build environment, chosen at compile time with `--dart-define=ENV=dev`.
///
/// Defaults to `prod`, so builds without the define are unchanged.
/// `ENV=dev` always uses the tashil-dev Firebase project and never falls back
/// to production. Any other value fails at startup.
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
    if (isDev) return dev.DefaultFirebaseOptions.currentPlatform;
    if (name == 'prod') return prod.DefaultFirebaseOptions.currentPlatform;
    throw UnsupportedError('Unknown ENV "$name". Use prod or dev.');
  }

  /// Same mapping as [firebaseOptions] for an explicit [env] (used in tests).
  static FirebaseOptions optionsFor(String env) {
    switch (env) {
      case 'prod':
        return prod.DefaultFirebaseOptions.currentPlatform;
      case 'dev':
        return dev.DefaultFirebaseOptions.currentPlatform;
      default:
        throw UnsupportedError('Unknown ENV "$env". Use prod or dev.');
    }
  }
}
