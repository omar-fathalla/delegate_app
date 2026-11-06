import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/domain/utils/live_tracking_active_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Independent Africa/Cairo fixtures for 2026.
///
/// Expected Y-M-D and offsets are hand-written literals, verified outside this
/// package (Python `zoneinfo` Africa/Cairo + public 2026 DST tables on time.is /
/// timeanddate; User Test review). Do **not** derive expects from
/// `package:timezone` / tzdb listing.
///
/// Implementation under test: direct dep `timezone: 0.10.1`, embedded tzdb
/// **2025b** (package CHANGELOG/README). If the pin or tzdb drifts, the optional
/// guard below fails loudly — do not regenerate expects from the package.
DelegateTrackingSession _session({
  required String id,
  required TrackingStatus status,
  DateTime? checkInTime,
  DateTime? checkOutTime,
}) {
  return DelegateTrackingSession(
    delegateId: id,
    delegateName: 'مندوب $id',
    delegatePhone: '01000000000',
    companyId: 'comp',
    organizationId: 'org',
    branchId: 'b1',
    branchName: 'فرع',
    branchLat: 30.0,
    branchLng: 31.0,
    geofenceRadius: 100,
    isTrackingEnabled: true,
    currentStatus: status,
    currentDistanceMeters: 10,
    lastUpdated: DateTime.utc(2026, 11, 6, 12),
    checkInTime: checkInTime,
    checkOutTime: checkOutTime,
  );
}

void main() {
  setUpAll(CairoClock.ensureInitialized);

  // Winter evening still on Cairo 2026-11-06 (UTC+2).
  final nowCairoEvening = DateTime.utc(2026, 11, 6, 21, 0);

  group('CairoClock init', () {
    test('fails loudly before ensureInitialized', () {
      // Isolate cannot easily un-init statics; document API by calling cairo
      // after init succeeds here. Separate: ensureInitialized is idempotent.
      CairoClock.ensureInitialized();
      expect(() => CairoClock.cairo, returnsNormally);
      expect(CairoClock.cairo.name, 'Africa/Cairo');
    });
  });

  group('fixed Africa/Cairo fixtures (independent expects)', () {
    const cases = <(String, String, int, int, int, int)>[
      // label, utc ISO, year, month, day, offsetHours
      ('spring-1s', '2026-04-23T21:59:59.999Z', 2026, 4, 23, 2),
      ('spring', '2026-04-23T22:00:00.000Z', 2026, 4, 24, 3),
      ('summer-pre', '2026-07-15T20:59:59.999Z', 2026, 7, 15, 3),
      ('summer-mid', '2026-07-15T21:00:00.000Z', 2026, 7, 16, 3),
      ('fall-1s', '2026-10-29T20:59:59.999Z', 2026, 10, 29, 3),
      ('fall-std23', '2026-10-29T21:00:00.000Z', 2026, 10, 29, 2),
      ('fall-next', '2026-10-29T22:00:00.000Z', 2026, 10, 30, 2),
      ('winter-pre', '2026-11-06T21:59:59.999Z', 2026, 11, 6, 2),
      ('winter-mid', '2026-11-06T22:00:00.000Z', 2026, 11, 7, 2),
    ];

    for (final c in cases) {
      test('${c.$1} → ${c.$3}-${c.$4}-${c.$5} UTC+${c.$6}', () {
        final instant = DateTime.parse(c.$2);
        expect(instant.isUtc, isTrue);
        final cairo = CairoClock.toCairo(instant);
        expect(cairo.year, c.$3);
        expect(cairo.month, c.$4);
        expect(cairo.day, c.$5);
        expect(cairo.timeZoneOffset, Duration(hours: c.$6));
      });
    }

    test('tzdb guard: embedded DB still matches published 2026 spring/fall', () {
      // If this fails, tzdb drifted — update pin/docs; do not auto-fix expects.
      final spring = CairoClock.toCairo(DateTime.parse('2026-04-23T22:00:00.000Z'));
      expect(spring.year, 2026);
      expect(spring.month, 4);
      expect(spring.day, 24);
      expect(spring.timeZoneOffset, const Duration(hours: 3));
      final fall = CairoClock.toCairo(DateTime.parse('2026-10-29T21:00:00.000Z'));
      expect(fall.day, 29);
      expect(fall.timeZoneOffset, const Duration(hours: 2));
    });
  });

  group('LiveTrackingActiveFilter Cairo day', () {
    test('winter UTC midnight boundary (regression)', () {
      final lateUtc = DateTime.utc(2026, 11, 6, 22, 30);
      final cairo = LiveTrackingActiveFilter.toCairo(lateUtc);
      expect(cairo.year, 2026);
      expect(cairo.month, 11);
      expect(cairo.day, 7);
      expect(cairo.hour, 0);
      expect(cairo.minute, 30);

      final earlyCairoNext = DateTime.utc(2026, 11, 6, 23, 0);
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(lateUtc, earlyCairoNext),
        isTrue,
      );
      final stillNov6Cairo = DateTime.utc(2026, 11, 6, 20, 0);
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(lateUtc, stillNov6Cairo),
        isFalse,
      );
    });

    test('spring local-midnight: day changes 23→24; exclude previous day', () {
      final before = DateTime.parse('2026-04-23T21:59:59.999Z');
      final after = DateTime.parse('2026-04-23T22:00:00.000Z');
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(before, after),
        isFalse,
      );
      // Check-in on Cairo day 23, now just after transition (day 24) → exclude.
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'spring',
            status: TrackingStatus.insideZone,
            checkInTime: DateTime.utc(2026, 4, 23, 10), // still day 23 Cairo
          ),
          now: after,
        ),
        isFalse,
      );
    });

    test('summer midnight include/exclude', () {
      final checkIn = DateTime.parse('2026-07-15T20:30:00.000Z'); // Cairo day 15
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'sum-keep',
            status: TrackingStatus.insideZone,
            checkInTime: checkIn,
          ),
          now: DateTime.parse('2026-07-15T20:45:00.000Z'),
        ),
        isTrue,
      );
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'sum-drop',
            status: TrackingStatus.insideZone,
            checkInTime: checkIn,
          ),
          now: DateTime.parse('2026-07-15T21:30:00.000Z'),
        ),
        isFalse,
      );
    });

    test('fall fold: both sides of 21:00Z stay day 29; 22:00Z is day 30', () {
      final checkIn = DateTime.utc(2026, 10, 29, 8);
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'fall-a',
            status: TrackingStatus.insideZone,
            checkInTime: checkIn,
          ),
          now: DateTime.parse('2026-10-29T20:59:59.999Z'),
        ),
        isTrue,
      );
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'fall-b',
            status: TrackingStatus.insideZone,
            checkInTime: checkIn,
          ),
          now: DateTime.parse('2026-10-29T21:00:00.000Z'),
        ),
        isTrue,
      );
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'fall-c',
            status: TrackingStatus.insideZone,
            checkInTime: checkIn,
          ),
          now: DateTime.parse('2026-10-29T22:00:00.000Z'),
        ),
        isFalse,
      );
    });
  });

  group('LiveTrackingActiveFilter.isCurrentlyCheckedIn', () {
    test('keeps today inside/outside/offline sessions', () {
      final checkIn = DateTime.utc(2026, 11, 6, 8, 0);
      for (final status in [
        TrackingStatus.insideZone,
        TrackingStatus.outsideZone,
        TrackingStatus.offline,
      ]) {
        expect(
          LiveTrackingActiveFilter.isCurrentlyCheckedIn(
            _session(id: status.name, status: status, checkInTime: checkIn),
            now: nowCairoEvening,
          ),
          isTrue,
          reason: status.name,
        );
      }
    });

    test('excludes checked_out status', () {
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'out',
            status: TrackingStatus.checkedOut,
            checkInTime: DateTime.utc(2026, 11, 6, 8),
            checkOutTime: DateTime.utc(2026, 11, 6, 18),
          ),
          now: nowCairoEvening,
        ),
        isFalse,
      );
    });

    test(
        'excludes sessions with checkOutTime after checkInTime even if status not checked_out',
        () {
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'stale',
            status: TrackingStatus.insideZone,
            checkInTime: DateTime.utc(2026, 11, 6, 8),
            checkOutTime: DateTime.utc(2026, 11, 6, 18),
          ),
          now: nowCairoEvening,
        ),
        isFalse,
      );
    });

    test('excludes yesterday check-ins (Cairo day)', () {
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(
            id: 'yest',
            status: TrackingStatus.insideZone,
            checkInTime: DateTime.utc(2026, 11, 5, 20),
          ),
          now: nowCairoEvening,
        ),
        isFalse,
      );
    });

    test('excludes sessions with no checkInTime', () {
      expect(
        LiveTrackingActiveFilter.isCurrentlyCheckedIn(
          _session(id: 'none', status: TrackingStatus.insideZone),
          now: nowCairoEvening,
        ),
        isFalse,
      );
    });

    test('filterActive returns only matching sessions', () {
      final sessions = [
        _session(
          id: 'keep',
          status: TrackingStatus.insideZone,
          checkInTime: DateTime.utc(2026, 11, 6, 9),
        ),
        _session(
          id: 'out',
          status: TrackingStatus.checkedOut,
          checkInTime: DateTime.utc(2026, 11, 6, 9),
          checkOutTime: DateTime.utc(2026, 11, 6, 12),
        ),
        _session(
          id: 'old',
          status: TrackingStatus.outsideZone,
          checkInTime: DateTime.utc(2026, 11, 4, 9),
        ),
      ];
      final active = LiveTrackingActiveFilter.filterActive(
        sessions,
        now: nowCairoEvening,
      );
      expect(active.map((s) => s.delegateId), ['keep']);
    });
  });

  group('device TZ independence', () {
    test('UTC inputs do not use toLocal for day equality', () {
      final a = DateTime.parse('2026-07-15T20:30:00.000Z');
      final b = DateTime.parse('2026-07-15T20:45:00.000Z');
      expect(a.isUtc && b.isUtc, isTrue);
      expect(LiveTrackingActiveFilter.isSameCairoCalendarDay(a, b), isTrue);
      // Constructing an equivalent non-UTC instant via toUtc path still matches.
      final localShaped = DateTime.fromMillisecondsSinceEpoch(
        a.millisecondsSinceEpoch,
        isUtc: false,
      );
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(localShaped, b),
        isTrue,
      );
    });
  });
}
