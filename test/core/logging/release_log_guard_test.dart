import 'package:delegate_app/core/logging/release_log_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DebugPrintCallback original;
  setUp(() => original = debugPrint);
  tearDown(() => debugPrint = original);

  test('release mode silences debugPrint', () {
    final seen = <String?>[];
    debugPrint = (String? m, {int? wrapWidth}) => seen.add(m);
    silenceDebugPrintInRelease(releaseMode: true);
    debugPrint('phone 01012345678');
    expect(seen, isEmpty);
  });

  test('debug mode keeps debugPrint', () {
    final seen = <String?>[];
    debugPrint = (String? m, {int? wrapWidth}) => seen.add(m);
    silenceDebugPrintInRelease(releaseMode: false);
    debugPrint('hello');
    expect(seen, ['hello']);
  });

  test('maskForLog keeps only the last digits', () {
    expect(maskForLog('01012345678'), '•••••••5678');
    expect(maskForLog('abc'), '•••');
    expect(maskForLog(null), '');
  });
}
