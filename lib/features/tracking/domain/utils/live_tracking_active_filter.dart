import 'package:delegate_app/core/time/cairo_clock.dart';

import '../entities/delegate_tracking_session.dart';

/// Filters [delegate_tracking] sessions down to delegates who are currently
/// checked in for live tracking.
///
/// "Today" is the Africa/Cairo civil calendar day (IANA, including DST), via
/// [CairoClock] — not a fixed UTC offset and not the device local zone.
class LiveTrackingActiveFilter {
  LiveTrackingActiveFilter._();

  /// Converts any [DateTime] to an Africa/Cairo wall-clock instant.
  /// Requires [CairoClock.ensureInitialized].
  static DateTime toCairo(DateTime value) => CairoClock.toCairo(value);

  static bool isSameCairoCalendarDay(DateTime a, DateTime b) =>
      CairoClock.isSameCairoCalendarDay(a, b);

  /// Whether [session] should appear on the Live Tracking screen right now.
  ///
  /// Excludes:
  /// - `currentStatus == checkedOut`
  /// - sessions with a [DelegateTrackingSession.checkOutTime] at/after check-in
  /// - sessions whose check-in is not today in Africa/Cairo
  /// - sessions with no check-in time (cannot prove they are today's attendance)
  static bool isCurrentlyCheckedIn(
    DelegateTrackingSession session, {
    required DateTime now,
  }) {
    if (session.currentStatus == TrackingStatus.checkedOut) {
      return false;
    }

    final checkIn = session.checkInTime;
    final checkOut = session.checkOutTime;
    if (checkOut != null) {
      if (checkIn == null || !checkOut.isBefore(checkIn)) {
        return false;
      }
    }

    if (checkIn == null) {
      return false;
    }

    return isSameCairoCalendarDay(checkIn, now);
  }

  static List<T> filterActive<T extends DelegateTrackingSession>(
    List<T> sessions, {
    required DateTime now,
  }) {
    return sessions
        .where((s) => isCurrentlyCheckedIn(s, now: now))
        .toList(growable: false);
  }
}
