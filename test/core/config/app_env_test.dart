import 'package:delegate_app/core/config/app_env.dart';
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

    test('dev on iOS throws', () {
      expect(
        () => AppEnv.ensureDevSupported(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        throwsUnsupportedError,
      );
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

    test('optionsFor dev throws with iOS platform override', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        () => AppEnv.optionsFor('dev', isWeb: false),
        throwsUnsupportedError,
      );
    });

    test('optionsFor prod on Android still works', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AppEnv.optionsFor('prod').projectId, 'practice-firebase-72df1');
    });
  });
}
