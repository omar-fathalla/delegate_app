import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/firebase_options.dart' as prod;
import 'package:delegate_app/firebase_options_dev.dart' as dev;
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
}
