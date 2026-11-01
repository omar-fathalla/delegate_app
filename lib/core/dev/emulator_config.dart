import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Local-only switch that points the app at the Firebase Emulator Suite.
///
///   flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
///   (Android emulator: add --dart-define=EMULATOR_HOST=10.0.2.2)
///
/// With the flag on, the app uses the demo project `demo-tashil-local`, so it
/// can never read or write production data. Off by default; release builds
/// never set it.
class EmulatorConfig {
  EmulatorConfig._();

  static const bool enabled = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  static const String host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');
  static const String projectId = 'demo-tashil-local';

  static FirebaseOptions options(FirebaseOptions base) =>
      enabled ? base.copyWith(projectId: projectId, storageBucket: '$projectId.appspot.com') : base;

  static bool _connected = false;

  static Future<void> connectIfEnabled() async {
    if (!enabled || _connected) return;
    _connected = true;
    debugPrint('*** USING FIREBASE EMULATORS at $host (project $projectId) ***');
    FirebaseFirestore.instance.settings = Settings(
      host: '$host:8080',
      sslEnabled: false,
      persistenceEnabled: false,
    );
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(host, 5001);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }
}
