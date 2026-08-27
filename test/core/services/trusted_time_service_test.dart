import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrustedTimeService Tests', () {
    test('now returns current time within reasonable threshold', () {
      final service = TrustedTimeService();
      final now = service.now;
      final localNow = DateTime.now();

      expect(
        now.difference(localNow).inSeconds.abs(),
        lessThanOrEqualTo(2),
      );

      service.dispose();
    });

    test('liveClockStream emits ticking time', () async {
      final service = TrustedTimeService();

      final firstTick = await service.liveClockStream.first;
      expect(firstTick, isNotNull);
      expect(
        firstTick.difference(DateTime.now()).inSeconds.abs(),
        lessThanOrEqualTo(2),
      );

      service.dispose();
    });
  });
}
