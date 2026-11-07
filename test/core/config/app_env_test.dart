import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';
import 'package:delegate_app/firebase_options.dart' as prod;
import 'package:delegate_app/firebase_options_dev.dart' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ENV defaults to prod', () {
    expect(AppEnv.name, 'prod');
    expect(AppEnv.isDev, isFalse);
  });

  test('prod uses the production Firebase project', () {
    expect(
      AppEnv.optionsFor('prod').projectId,
      prod.DefaultFirebaseOptions.web.projectId,
    );
    expect(
      prod.DefaultFirebaseOptions.web.projectId,
      'practice-firebase-72df1',
    );
  });

  test('dev uses tashil-dev and never production', () {
    expect(dev.DefaultFirebaseOptions.web.projectId, 'tashil-dev');
    expect(dev.DefaultFirebaseOptions.android.projectId, 'tashil-dev');
  });

  test('dev options never point at production', () {
    for (final o in [
      dev.DefaultFirebaseOptions.web,
      dev.DefaultFirebaseOptions.android,
      dev.DefaultFirebaseOptions.ios,
    ]) {
      expect(o.projectId, 'tashil-dev');
      expect(o.appId, isNot(contains('564223619997')));
      expect(o.storageBucket, isNot(contains('practice-firebase-72df1')));
    }
  });

  test('verifyFirebaseProject fails closed on a project mismatch', () {
    expect(
      () => AppEnv.verifyFirebaseProjectFor('dev', 'tashil-dev'),
      returnsNormally,
    );
    expect(
      () => AppEnv.verifyFirebaseProjectFor('dev', 'practice-firebase-72df1'),
      throwsStateError,
    );
    expect(
      () => AppEnv.verifyFirebaseProjectFor('prod', 'tashil-dev'),
      throwsStateError,
    );
    expect(AppEnv.expectedProjectId, 'practice-firebase-72df1');
  });

  test('Crashlytics is enabled only for prod builds', () {
    // Tests run with the default ENV (prod).
    expect(CrashlyticsService.enabledForEnv, isTrue);
  });

  test('unknown ENV fails instead of falling back', () {
    expect(() => AppEnv.optionsFor('staging'), throwsUnsupportedError);
  });
  group('ENV=dev platform support', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('dev on Android is allowed (dev flavor)', () {
      expect(
        () => AppEnv.ensureDevSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        returnsNormally,
      );
    });

    test('dev on iOS is allowed (dev flavor)', () {
      expect(
        () => AppEnv.ensureDevSupported(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        returnsNormally,
      );
    });

    test('dev on macOS/Windows/Linux still fails closed', () {
      for (final p in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          () => AppEnv.ensureDevSupported(isWeb: false, platform: p),
          throwsUnsupportedError,
        );
      }
    });

    test('dev on web is allowed', () {
      expect(
        () => AppEnv.ensureDevSupported(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        returnsNormally,
      );
    });

    test('optionsFor dev on Android uses the tashil-dev dev-flavor app', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final o = AppEnv.optionsFor('dev', isWeb: false);
      expect(o.projectId, 'tashil-dev');
      expect(o.appId, '1:582609039627:android:40c38c45d1bdb99add720e');
    });

    test('optionsFor dev on iOS uses the tashil-dev iOS app', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final o = AppEnv.optionsFor('dev', isWeb: false);
      expect(o.projectId, 'tashil-dev');
      expect(o.appId, '1:582609039627:ios:0a788355f5bc4886dd720e');
      expect(o.iosBundleId, 'com.tashil.delegate.dev');
      expect(o.messagingSenderId, isNot('564223619997'));
    });

    test('optionsFor prod on Android still works', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AppEnv.optionsFor('prod').projectId, 'practice-firebase-72df1');
    });
  });
}
