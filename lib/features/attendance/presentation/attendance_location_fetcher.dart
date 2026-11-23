import 'dart:async';

import 'package:geolocator/geolocator.dart';

typedef CurrentPositionGetter = Future<Position> Function(
  LocationSettings settings,
);
typedef LastKnownPositionGetter = Future<Position?> Function();

/// Where a [LocationFix] came from.
enum LocationFixSource { fresh, lastKnown }

class LocationFix {
  const LocationFix(this.position, this.source);

  final Position position;
  final LocationFixSource source;
}

/// Gets the delegate's position for attendance (TAS-278).
///
/// Weak phones (e.g. OPPO A5s) often need more than 6 s for a first GPS fix
/// indoors, so this tries a high-accuracy fix, then a medium one, before it
/// falls back to the phone's last known position (TAS-279). The last known
/// position is only used when it is recent and precise enough, because an old
/// one can match the wrong branch (TAS-161, TAS-280).
class AttendanceLocationFetcher {
  AttendanceLocationFetcher({
    CurrentPositionGetter? getCurrentPosition,
    LastKnownPositionGetter? getLastKnownPosition,
    DateTime Function()? now,
    this.highAccuracyTimeout = const Duration(seconds: 10),
    this.mediumAccuracyTimeout = const Duration(seconds: 10),
    this.maxLastKnownAge = const Duration(minutes: 2),
    this.maxLastKnownAccuracyMeters = 100,
  })  : _getCurrentPosition = getCurrentPosition ??
            ((settings) =>
                Geolocator.getCurrentPosition(locationSettings: settings)),
        _getLastKnownPosition =
            getLastKnownPosition ?? Geolocator.getLastKnownPosition,
        _now = now ?? DateTime.now;

  final CurrentPositionGetter _getCurrentPosition;
  final LastKnownPositionGetter _getLastKnownPosition;
  final DateTime Function() _now;

  final Duration highAccuracyTimeout;
  final Duration mediumAccuracyTimeout;
  final Duration maxLastKnownAge;
  final double maxLastKnownAccuracyMeters;

  /// Returns null when no usable position was found in time. Other errors
  /// (service off, permission) are rethrown for the caller.
  Future<LocationFix?> fetch() async {
    for (final settings in [
      LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: highAccuracyTimeout,
      ),
      LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: mediumAccuracyTimeout,
      ),
    ]) {
      try {
        final position = await _getCurrentPosition(settings);
        return LocationFix(position, LocationFixSource.fresh);
      } on TimeoutException {
        // Try the next, less demanding request.
      }
    }

    final last = await _getLastKnownPosition();
    if (last == null) return null;
    // A mocked position is always returned so the caller can log the
    // fake-GPS violation, whatever its age.
    if (last.isMocked || isUsableLastKnown(last)) {
      return LocationFix(last, LocationFixSource.lastKnown);
    }
    return null;
  }

  /// True when [position] is recent and precise enough to stand in for a
  /// live fix.
  bool isUsableLastKnown(Position position) {
    final age = _now().difference(position.timestamp).abs();
    return age <= maxLastKnownAge &&
        position.accuracy <= maxLastKnownAccuracyMeters;
  }
}
