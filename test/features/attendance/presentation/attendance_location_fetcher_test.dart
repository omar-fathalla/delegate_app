import 'dart:async';

import 'package:delegate_app/features/attendance/presentation/attendance_location_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

final _now = DateTime.utc(2026, 11, 23, 10);

Position _pos({
  Duration age = Duration.zero,
  double accuracy = 15,
  bool mocked = false,
  double lat = 30.0,
}) =>
    Position(
      latitude: lat,
      longitude: 31.0,
      timestamp: _now.subtract(age),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

AttendanceLocationFetcher _fetcher({
  required List<Object> current, // Position or TimeoutException, in order
  Position? lastKnown,
  List<LocationAccuracy>? seen,
}) {
  var i = 0;
  return AttendanceLocationFetcher(
    now: () => _now,
    getCurrentPosition: (settings) async {
      seen?.add(settings.accuracy);
      final r = current[i++];
      if (r is Position) return r;
      throw r;
    },
    getLastKnownPosition: () async => lastKnown,
  );
}

void main() {
  group('AttendanceLocationFetcher (TAS-279/TAS-280)', () {
    test('uses the high-accuracy fix when it arrives in time', () async {
      final seen = <LocationAccuracy>[];
      final fix = await _fetcher(current: [_pos(lat: 1)], seen: seen).fetch();
      expect(fix!.source, LocationFixSource.fresh);
      expect(fix.position.latitude, 1);
      expect(seen, [LocationAccuracy.high]);
    });

    test('falls back to medium accuracy after a high-accuracy timeout',
        () async {
      final seen = <LocationAccuracy>[];
      final fix = await _fetcher(
        current: [TimeoutException('gps'), _pos(lat: 2)],
        seen: seen,
      ).fetch();
      expect(fix!.source, LocationFixSource.fresh);
      expect(fix.position.latitude, 2);
      expect(seen, [LocationAccuracy.high, LocationAccuracy.medium]);
    });

    test('gives the GPS up to 20 s in total, not 6 s', () {
      final f = AttendanceLocationFetcher();
      expect(
        f.highAccuracyTimeout + f.mediumAccuracyTimeout,
        const Duration(seconds: 20),
      );
    });

    test('accepts a last known position that is 30 s old', () async {
      final fix = await _fetcher(
        current: [TimeoutException('a'), TimeoutException('b')],
        lastKnown: _pos(age: const Duration(seconds: 30), lat: 3),
      ).fetch();
      expect(fix!.source, LocationFixSource.lastKnown);
      expect(fix.position.latitude, 3);
    });

    test('rejects a last known position that is 10 minutes old (TAS-161)',
        () async {
      final fix = await _fetcher(
        current: [TimeoutException('a'), TimeoutException('b')],
        lastKnown: _pos(age: const Duration(minutes: 10)),
      ).fetch();
      expect(fix, isNull);
    });

    test('rejects an imprecise last known position', () async {
      final fix = await _fetcher(
        current: [TimeoutException('a'), TimeoutException('b')],
        lastKnown: _pos(age: const Duration(seconds: 10), accuracy: 800),
      ).fetch();
      expect(fix, isNull);
    });

    test('returns null when there is no position at all', () async {
      final fix = await _fetcher(
        current: [TimeoutException('a'), TimeoutException('b')],
      ).fetch();
      expect(fix, isNull);
    });

    test('still returns an old mocked position so fake GPS gets logged',
        () async {
      final fix = await _fetcher(
        current: [TimeoutException('a'), TimeoutException('b')],
        lastKnown: _pos(age: const Duration(hours: 1), mocked: true),
      ).fetch();
      expect(fix!.position.isMocked, isTrue);
    });

    test('rethrows errors other than a timeout', () async {
      final f = _fetcher(current: [const LocationServiceDisabledException()]);
      expect(f.fetch(), throwsA(isA<LocationServiceDisabledException>()));
    });
  });

  group('isRecentLastKnownFix (TAS-161)', () {
    bool check({
      Duration? age = const Duration(seconds: 30),
      double? accuracy = 20,
    }) =>
        isRecentLastKnownFix(
          timestamp: age == null ? null : _now.subtract(age),
          accuracyMeters: accuracy,
          now: _now,
        );

    test('accepts a fresh, precise fix', () {
      expect(check(), isTrue);
      expect(check(age: Duration.zero), isTrue);
      expect(check(age: const Duration(minutes: 2)), isTrue);
    });

    test('rejects a stale fix', () {
      expect(check(age: const Duration(minutes: 2, seconds: 1)), isFalse);
      expect(check(age: const Duration(hours: 3)), isFalse);
    });

    test('rejects a fix stamped at the epoch (unknown time)', () {
      expect(
        isRecentLastKnownFix(
          timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          accuracyMeters: 10,
          now: _now,
        ),
        isFalse,
      );
    });

    test('rejects a null timestamp', () {
      expect(check(age: null), isFalse);
    });

    test('rejects poor or unknown accuracy', () {
      expect(check(accuracy: 100), isTrue);
      expect(check(accuracy: 101), isFalse);
      expect(check(accuracy: 3900), isFalse);
      expect(check(accuracy: 0), isFalse);
      expect(check(accuracy: -1), isFalse);
      expect(check(accuracy: double.nan), isFalse);
      expect(check(accuracy: double.infinity), isFalse);
      expect(check(accuracy: null), isFalse);
    });

    test('tolerates a small clock skew but not a far-future stamp', () {
      expect(check(age: const Duration(seconds: -20)), isTrue);
      expect(check(age: const Duration(minutes: -5)), isFalse);
    });
  });

  test('fetcher drops a last known fix with unknown (0 m) accuracy', () async {
    final fix = await _fetcher(
      current: [TimeoutException('a'), TimeoutException('b')],
      lastKnown: _pos(age: const Duration(seconds: 5), accuracy: 0),
    ).fetch();
    expect(fix, isNull);
  });
}
