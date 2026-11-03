import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/core/config/debug_stall.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final withParam = Uri.parse('https://x.web.app/?debugStall=1');
  final hashParam = Uri.parse('https://x.web.app/#/?debugStall=1');

  test('prod never stalls, even with the param', () {
    for (final env in ['prod', '', 'production', 'DEV']) {
      expect(debugStallActiveFor(env: env, isWeb: true, uri: withParam), isFalse);
      expect(debugStallActiveFor(env: env, isWeb: true, uri: hashParam), isFalse);
    }
  });

  test('default build (no ENV define = prod) is off', () {
    expect(AppEnv.isDev, isFalse);
    expect(debugStallActive, isFalse);
  });

  test('dev web honours ?debugStall=1 only', () {
    expect(debugStallActiveFor(env: 'dev', isWeb: true, uri: withParam), isTrue);
    expect(debugStallActiveFor(env: 'dev', isWeb: true, uri: hashParam), isTrue);
    expect(
      debugStallActiveFor(env: 'dev', isWeb: true, uri: Uri.parse('https://x/?debugStall=0')),
      isFalse,
    );
    expect(debugStallActiveFor(env: 'dev', isWeb: false, uri: withParam), isFalse);
  });
}
