import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-364: «التتبع واقف» after 15 minutes without a signal while checked in,
/// and the shift notification of the Android foreground service.
void main() {
  final now = DateTime(2026, 11, 28, 12);

  DelegateTrackingSession session(TrackingStatus status, Duration age) => DelegateTrackingSession(
        delegateId: 'd1',
        delegateName: 'fake',
        delegatePhone: '01000000000',
        companyId: 'c1',
        organizationId: 'o1',
        branchId: 'b1',
        branchName: 'Fake Alpha',
        branchLat: 30,
        branchLng: 31,
        geofenceRadius: 100,
        isTrackingEnabled: true,
        currentStatus: status,
        currentDistanceMeters: 10,
        lastLatitude: 30,
        lastLongitude: 31,
        lastUpdated: now.subtract(age),
        checkInTime: now.subtract(const Duration(hours: 3)),
      );

  test('checked in and silent for more than 15 min = stale', () {
    expect(session(TrackingStatus.insideZone, const Duration(minutes: 16)).isTrackingStaleAt(now), isTrue);
    expect(session(TrackingStatus.outsideZone, const Duration(minutes: 40)).isTrackingStaleAt(now), isTrue);
  });

  test('a recent signal, or a checked-out delegate, is not stale', () {
    expect(session(TrackingStatus.insideZone, const Duration(minutes: 5)).isTrackingStaleAt(now), isFalse);
    expect(session(TrackingStatus.checkedOut, const Duration(hours: 5)).isTrackingStaleAt(now), isFalse);
  });

  test('the shift notification keeps the service in the foreground', () {
    final n = trackingForegroundNotification();
    expect(n.notificationTitle, 'تسهيل: الشيفت شغال');
    expect(n.setOngoing, isTrue);
    expect(n.enableWakeLock, isTrue);
  });
}
