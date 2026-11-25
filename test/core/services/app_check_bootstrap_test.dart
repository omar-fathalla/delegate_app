import 'package:delegate_app/core/services/app_check_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TAS-16 App Check provider choice', () {
    test('prod release build uses the real attestation providers', () {
      expect(
        appCheckUsesDebugProvider(isDev: false, releaseMode: true),
        isFalse,
      );
    });

    test('dev builds use the debug provider, even in release mode', () {
      expect(appCheckUsesDebugProvider(isDev: true, releaseMode: true), isTrue);
      expect(
        appCheckUsesDebugProvider(isDev: true, releaseMode: false),
        isTrue,
      );
    });

    test('non-release prod builds use the debug provider', () {
      expect(
        appCheckUsesDebugProvider(isDev: false, releaseMode: false),
        isTrue,
      );
    });
  });
}
