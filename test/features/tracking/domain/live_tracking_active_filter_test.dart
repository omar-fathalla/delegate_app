import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/domain/utils/live_tracking_active_filter.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // 2026-11-06 21:00 UTC == 2026-11-06 23:00 Cairo (UTC+2)
  final nowCairoEvening = DateTime.utc(2026, 11, 6, 21, 0);

  group('LiveTrackingActiveFilter Cairo day', () {
    test('toCairo applies permanent UTC+2 offset', () {
      final cairo = LiveTrackingActiveFilter.toCairo(
        DateTime.utc(2026, 11, 6, 22, 30),
      );
      expect(cairo.year, 2026);
      expect(cairo.month, 11);
      expect(cairo.day, 7); // 22:30 UTC + 2h = 00:30 next day Cairo
      expect(cairo.hour, 0);
      expect(cairo.minute, 30);
    });

    test('isSameCairoCalendarDay crosses UTC midnight correctly', () {
      // 22:30 UTC Nov 6 == 00:30 Cairo Nov 7
      final lateUtc = DateTime.utc(2026, 11, 6, 22, 30);
      final earlyCairoNext = DateTime.utc(2026, 11, 6, 23, 0); // 01:00 Cairo Nov 7
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(lateUtc, earlyCairoNext),
        isTrue,
      );
      final stillNov6Cairo = DateTime.utc(2026, 11, 6, 20, 0); // 22:00 Cairo Nov 6
      expect(
        LiveTrackingActiveFilter.isSameCairoCalendarDay(lateUtc, stillNov6Cairo),
        isFalse,
      );
    });
  });

  group('LiveTrackingActiveFilter.isCurrentlyCheckedIn', () {
    test('keeps today inside/outside/offline sessions', () {
      final checkIn = DateTime.utc(2026, 11, 6, 8, 0); // 10:00 Cairo
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

    test('excludes sessions with checkOutTime after checkInTime even if status not checked_out',
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
      // Yesterday 20:00 UTC = 22:00 Cairo Nov 5
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
}
