import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Africa/Cairo helpers for civil calendar days (Live Tracking, etc.).
///
/// Uses [package:timezone] with an explicit cached [tz.Location] for
/// `Africa/Cairo`. Never calls [tz.setLocalLocation] and never uses device
/// local / [DateTime.toLocal] for day math.
///
/// Pinned dependency: `timezone: 0.10.1` (embedded IANA tzdb **2025b**).
class CairoClock {
  CairoClock._();

  static bool _initialized = false;
  static tz.Location? _cairo;

  /// Eager init — call from every app entrypoint and from test `setUpAll`.
  /// Safe to call more than once.
  static void ensureInitialized() {
    if (_initialized && _cairo != null) return;
    tzdata.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
    _initialized = true;
  }

  static tz.Location get cairo {
    final loc = _cairo;
    if (!_initialized || loc == null) {
      throw StateError(
        'CairoClock.ensureInitialized() must run before Africa/Cairo helpers '
        '(main.dart / main_real_test.dart / test setUpAll).',
      );
    }
    return loc;
  }

  /// Wall-clock components in Africa/Cairo for an absolute instant.
  /// [value] is converted with `.toUtc()` first — never via device local.
  static tz.TZDateTime toCairo(DateTime value) {
    return tz.TZDateTime.from(value.toUtc(), cairo);
  }

  static bool isSameCairoCalendarDay(DateTime a, DateTime b) {
    final ca = toCairo(a);
    final cb = toCairo(b);
    return ca.year == cb.year && ca.month == cb.month && ca.day == cb.day;
  }
}
