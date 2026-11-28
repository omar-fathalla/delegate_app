import 'boot_clock.dart';

class _NoBootClock implements BootClock {
  @override
  int? elapsedMs() => null;
}

BootClock createSystemBootClock() => _NoBootClock();
