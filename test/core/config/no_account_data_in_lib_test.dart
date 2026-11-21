import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-78: lib/ must not carry a real account's uid / email / org id; the
/// real-test entrypoint takes them from dart-defines and requires ENV.
void main() {
  test('main_real_test.dart has no hardcoded account values', () {
    final src = File('lib/main_real_test.dart').readAsStringSync();
    expect(src, isNot(contains('O0LHjrZU7TXG5LHi9QcqavE4i1q1')));
    expect(src, isNot(contains('probe.tashil.test1@gmail.com')));
    expect(src, isNot(contains('PiioBFgxaHAeuRdjlDgj')));
    expect(src, contains("bool.hasEnvironment('ENV')"));
    expect(src, contains('AppEnv.firebaseOptions'));
    expect(src, isNot(contains('DefaultFirebaseOptions.currentPlatform')));
  });
}
