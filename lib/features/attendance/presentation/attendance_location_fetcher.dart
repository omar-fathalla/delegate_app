import 'dart:async';

import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:geolocator/geolocator.dart';

typedef CurrentPositionGetter =
    Future<Position> Function(LocationSettings settings);
typedef LastKnownPositionGetter = Future<Position?> Function();

/// Where a [LocationFix] came from.
enum LocationFixSource { fresh, lastKnown }

class LocationFix {
  const LocationFix(this.position, this.source);

  final Position position;
  final LocationFixSource source;
}

/// Why a cached (last known) position was not accepted (TAS-396).
enum LastKnownRejection {
  /// Older than the allowed age.
  stale,

  /// Known accuracy, but worse than the allowed limit.
  inaccurate,

  /// Age or accuracy cannot be judged (null, 0, NaN, or stamped in the
  /// future).
  unknown,
}

/// What the delegate is told when no usable position was found (TAS-396).
enum LocationFetchFailureReason {
  /// No live fix in time and no usable last known position.
  noFix,

  /// The phone has a position, but it is too imprecise (weak signal, e.g.
  /// indoors).
  weakSignal,
}

/// Why [AttendanceLocationFetcher.fetch] returned null.
class LocationFetchFailure {
  const LocationFetchFailure(
    this.reason, {
    this.lastKnownRejection,
    this.accuracyMeters,
  });

  final LocationFetchFailureReason reason;

  /// Set when a last known position existed but was rejected.
  final LastKnownRejection? lastKnownRejection;

  /// Accuracy of the rejected last known position, in metres.
  final double? accuracyMeters;
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
  }) : _getCurrentPosition =
           getCurrentPosition ??
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

  LocationFetchFailure? _lastFailure;

  /// Why the last [fetch] returned null; null after a successful fetch.
  LocationFetchFailure? get lastFailure => _lastFailure;

  /// Returns null when no usable position was found in time; [lastFailure]
  /// then says why (TAS-396). Other errors (service off, permission) are
  /// rethrown for the caller.
  Future<LocationFix?> fetch() async {
    _lastFailure = null;
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
    if (last == null) {
      _lastFailure = const LocationFetchFailure(
        LocationFetchFailureReason.noFix,
      );
      return null;
    }
    // A mocked position is always returned so the caller can log the
    // fake-GPS violation, whatever its age.
    if (last.isMocked) {
      return LocationFix(last, LocationFixSource.lastKnown);
    }
    final rejection = lastKnownRejectionOf(last);
    if (rejection == null) {
      return LocationFix(last, LocationFixSource.lastKnown);
    }
    _lastFailure = LocationFetchFailure(
      rejection == LastKnownRejection.inaccurate
          ? LocationFetchFailureReason.weakSignal
          : LocationFetchFailureReason.noFix,
      lastKnownRejection: rejection,
      accuracyMeters: last.accuracy,
    );
    return null;
  }

  /// Why [position] may not stand in for a live fix; null when it may.
  LastKnownRejection? lastKnownRejectionOf(Position position) =>
      lastKnownRejection(
        timestamp: position.timestamp,
        accuracyMeters: position.accuracy,
        now: _now(),
        maxAge: maxLastKnownAge,
        maxAccuracyMeters: maxLastKnownAccuracyMeters,
      );

  /// True when [position] is recent and precise enough to stand in for a
  /// live fix.
  bool isUsableLastKnown(Position position) =>
      lastKnownRejectionOf(position) == null;
}

/// How far in the future a last known fix may be stamped and still count:
/// small clock differences between the GPS chip and the phone are normal.
const Duration lastKnownClockSkewTolerance = Duration(seconds: 30);

/// Decides whether a cached (last known) position may stand in for a live GPS
/// fix when judging a delegate's distance to a branch (TAS-161, TAS-280).
///
/// A stale fix can sit near another branch kilometres away, so it is only
/// accepted when all of these hold:
/// * [timestamp] is known (null means the age cannot be judged);
/// * it is at most [maxAge] old, and not more than
///   [lastKnownClockSkewTolerance] in the future;
/// * [accuracyMeters] is a real, positive value no larger than
///   [maxAccuracyMeters] (Android reports 0 when the accuracy is unknown).
///
/// This only filters genuine fixes. Mock-location handling stays with the
/// caller and must never be relaxed because of this check.
bool isRecentLastKnownFix({
  required DateTime? timestamp,
  required double? accuracyMeters,
  required DateTime now,
  Duration maxAge = const Duration(minutes: 2),
  double maxAccuracyMeters = 100,
}) =>
    lastKnownRejection(
      timestamp: timestamp,
      accuracyMeters: accuracyMeters,
      now: now,
      maxAge: maxAge,
      maxAccuracyMeters: maxAccuracyMeters,
    ) ==
    null;

/// Same limits as [isRecentLastKnownFix], but says why a fix is rejected
/// (TAS-396). Returns null when the fix is accepted. Cases whose age or
/// accuracy cannot be judged are [LastKnownRejection.unknown].
LastKnownRejection? lastKnownRejection({
  required DateTime? timestamp,
  required double? accuracyMeters,
  required DateTime now,
  Duration maxAge = const Duration(minutes: 2),
  double maxAccuracyMeters = 100,
}) {
  if (timestamp == null || accuracyMeters == null) {
    return LastKnownRejection.unknown;
  }
  final age = now.difference(timestamp);
  if (age < -lastKnownClockSkewTolerance) return LastKnownRejection.unknown;
  if (accuracyMeters.isNaN ||
      accuracyMeters.isInfinite ||
      accuracyMeters <= 0) {
    return LastKnownRejection.unknown;
  }
  if (age > maxAge) return LastKnownRejection.stale;
  if (accuracyMeters > maxAccuracyMeters) return LastKnownRejection.inaccurate;
  return null;
}

/// Accuracy (metres) worse than this counts as a weak signal when the
/// delegate looks just outside a branch (TAS-396).
const double weakSignalAccuracyMeters = 50;

/// True when a delegate who is outside the geofence on paper may well be
/// inside it: the fix is imprecise (worse than [weakSignalAccuracyMeters])
/// and the error circle reaches the allowed radius. Only the message changes;
/// the geofence decision itself stays `distance <= radius` (TAS-396).
bool isOutsideBecauseOfWeakSignal({
  required double distanceMeters,
  required double accuracyMeters,
  required double radiusMeters,
}) {
  if (accuracyMeters.isNaN || accuracyMeters.isInfinite) return false;
  if (accuracyMeters <= weakSignalAccuracyMeters) return false;
  if (distanceMeters <= radiusMeters) return false;
  return distanceMeters - accuracyMeters <= radiusMeters;
}

/// The snackbar text for a failed [AttendanceLocationFetcher.fetch]
/// (TAS-396): weak signal when the phone only had an imprecise position,
/// otherwise the general no-location message.
String locationFailureMessage(
  AppLocalizations l10n,
  LocationFetchFailure? failure,
) => failure?.reason == LocationFetchFailureReason.weakSignal
    ? l10n.locationWeakSignal
    : l10n.locationTimeout;
