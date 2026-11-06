import '../entities/delegate_tracking_session.dart';

/// Filters [delegate_tracking] sessions down to delegates who are currently
/// checked in for live tracking.
///
/// Egypt (Africa/Cairo) is permanently UTC+2 (no DST). We convert via UTC then
/// apply that fixed offset so "today" matches Cairo calendar days regardless of
/// the device's local zone.
class LiveTrackingActiveFilter {
  LiveTrackingActiveFilter._();

  static const Duration cairoOffsetFromUtc = Duration(hours: 2);

  /// Converts any [DateTime] to a Cairo wall-clock [DateTime] (not a true TZ
  /// type — year/month/day are what callers need for day comparisons).
  static DateTime toCairo(DateTime value) =>
      value.toUtc().add(cairoOffsetFromUtc);

  static bool isSameCairoCalendarDay(DateTime a, DateTime b) {
    final ca = toCairo(a);
    final cb = toCairo(b);
    return ca.year == cb.year && ca.month == cb.month && ca.day == cb.day;
  }

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
