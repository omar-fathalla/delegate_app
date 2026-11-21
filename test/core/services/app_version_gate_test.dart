import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements AppVersionGateSource {
  _FakeSource(this.values, {this.prepareError, this.prepareDelay});

  final AppVersionGateValues values;
  final Object? prepareError;
  final Duration? prepareDelay;

  @override
  Future<void> prepare() async {
    if (prepareDelay != null) await Future<void>.delayed(prepareDelay!);
    if (prepareError != null) throw prepareError!;
  }

  @override
  AppVersionGateValues read() => values;
}

void main() {
  setUp(AppVersionGate.debugReset);

  group('parseVersion / compareVersions', () {
    test('parses major.minor.patch and the build number', () {
      expect(parseVersion('1.14.3'), [1, 14, 3]);
      expect(parseVersion('1.14.3+45'), [1, 14, 3, 45]);
      expect(parseVersion(' 2.0 '), [2, 0]);
    });

    test('rejects anything that is not numeric', () {
      expect(parseVersion(''), isNull);
      expect(parseVersion('abc'), isNull);
      expect(parseVersion('1.x.3'), isNull);
      expect(parseVersion('1.-2'), isNull);
    });

    test('compares numerically, not lexically', () {
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.15', '1.15.0'), 0);
      expect(compareVersions('1.15.0+120', '1.15.0'), greaterThan(0));
      expect(compareVersions('1.15.0', '1.15.0+1'), lessThan(0));
    });

    test('unparsable input compares as equal', () {
      expect(compareVersions('oops', '1.0.0'), 0);
    });
  });

  group('evaluate', () {
    const values = AppVersionGateValues(
      minVersionAndroid: '1.15.0',
      minVersionIos: '1.16.0',
      storeUrlIos: 'https://apps.apple.com/app/id123',
    );

    test('blocks an Android build below the Android minimum', () {
      final d = AppVersionGate.evaluate(
        values: values,
        currentVersion: '1.14.9',
        platform: TargetPlatform.android,
      );
      expect(d.updateRequired, isTrue);
      expect(d.minVersion, '1.15.0');
      expect(d.storeUrl, AppVersionGate.defaultPlayStoreUrl);
    });

    test('allows an Android build at or above the minimum', () {
      for (final v in ['1.15.0', '1.15.0+3', '1.16.2']) {
        final d = AppVersionGate.evaluate(
          values: values,
          currentVersion: v,
          platform: TargetPlatform.android,
        );
        expect(d.updateRequired, isFalse, reason: v);
      }
    });

    test('uses the iOS minimum and the configured iOS store url', () {
      final d = AppVersionGate.evaluate(
        values: values,
        currentVersion: '1.15.0',
        platform: TargetPlatform.iOS,
      );
      expect(d.updateRequired, isTrue);
      expect(d.storeUrl, 'https://apps.apple.com/app/id123');
    });

    test('an empty minimum never blocks', () {
      final d = AppVersionGate.evaluate(
        values: const AppVersionGateValues(),
        currentVersion: '0.0.1',
        platform: TargetPlatform.android,
      );
      expect(d, AppVersionGateDecision.allowed);
    });

    test('an unparsable minimum or current version never blocks', () {
      expect(
        AppVersionGate.evaluate(
          values: const AppVersionGateValues(minVersionAndroid: 'soon'),
          currentVersion: '1.0.0',
          platform: TargetPlatform.android,
        ).updateRequired,
        isFalse,
      );
      expect(
        AppVersionGate.evaluate(
          values: values,
          currentVersion: 'dev-build',
          platform: TargetPlatform.android,
        ).updateRequired,
        isFalse,
      );
    });
  });

  group('refresh', () {
    test('publishes a blocking decision and completes ready', () async {
      final source = _FakeSource(
        const AppVersionGateValues(minVersionAndroid: '2.0.0'),
      );
      final refresh = AppVersionGate.refresh(
        source: source,
        currentVersion: '1.9.9',
        platform: TargetPlatform.android,
        isWeb: false,
      );
      await AppVersionGate.ready;
      await refresh;
      expect(AppVersionGate.isBlocked, isTrue);
      expect(AppVersionGate.decision.value.minVersion, '2.0.0');
    });

    test('fails open when the source throws', () async {
      final source = _FakeSource(
        const AppVersionGateValues(minVersionAndroid: '2.0.0'),
        prepareError: StateError('offline'),
      );
      await AppVersionGate.refresh(
        source: source,
        currentVersion: '1.0.0',
        platform: TargetPlatform.android,
        isWeb: false,
      );
      expect(AppVersionGate.isBlocked, isFalse);
    });

    test('fails open when the source times out', () async {
      final source = _FakeSource(
        const AppVersionGateValues(minVersionAndroid: '2.0.0'),
        prepareDelay: const Duration(milliseconds: 200),
      );
      await AppVersionGate.refresh(
        source: source,
        currentVersion: '1.0.0',
        platform: TargetPlatform.android,
        isWeb: false,
        timeout: const Duration(milliseconds: 20),
      );
      expect(AppVersionGate.isBlocked, isFalse);
    });

    test('never gates the web build', () async {
      final source = _FakeSource(
        const AppVersionGateValues(minVersionAndroid: '2.0.0'),
      );
      await AppVersionGate.refresh(
        source: source,
        currentVersion: '1.0.0',
        platform: TargetPlatform.android,
        isWeb: true,
      );
      expect(AppVersionGate.isBlocked, isFalse);
    });

    test('ready completes immediately when no refresh was started', () async {
      await AppVersionGate.ready.timeout(const Duration(milliseconds: 50));
    });

    test('notifies listeners when the decision changes', () async {
      var notified = 0;
      void listener() => notified++;
      AppVersionGate.decision.addListener(listener);
      addTearDown(() => AppVersionGate.decision.removeListener(listener));
      await AppVersionGate.refresh(
        source: _FakeSource(
          const AppVersionGateValues(minVersionAndroid: '9.0.0'),
        ),
        currentVersion: '1.0.0',
        platform: TargetPlatform.android,
        isWeb: false,
      );
      expect(notified, 1);
    });
  });
}
