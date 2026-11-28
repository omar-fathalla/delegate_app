import 'boot_clock_stub.dart'
    if (dart.library.ffi) 'boot_clock_ffi.dart'
    as impl;

/// Milliseconds since the device booted, counting deep sleep (TAS-363).
///
/// Android: `CLOCK_BOOTTIME` (same as `SystemClock.elapsedRealtime()`).
/// iOS: `CLOCK_MONOTONIC`, which on Darwin keeps counting while asleep.
/// Neither moves when the user changes the phone's clock; both restart from
/// zero after a reboot. Returns null where it is not available (web, tests).
abstract class BootClock {
  int? elapsedMs();

  /// The real clock of the platform (null on web).
  static BootClock system() => impl.createSystemBootClock();
}
