import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cairo helpers throw before ensureInitialized', () {
    expect(
      () => CairoClock.toCairo(DateTime.utc(2026, 1, 1)),
      throwsA(isA<StateError>()),
    );
  });
}
