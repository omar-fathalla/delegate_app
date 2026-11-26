import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/domain/utils/tracking_geofence_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

DelegateTrackingSession _base(TrackingStatus status) {
  return DelegateTrackingSession(
    delegateId: 'd1',
    delegateName: 'مندوب',
    delegatePhone: '010',
    companyId: 'c1',
    organizationId: 'o1',
    branchId: 'b1',
    branchName: 'فرع',
    branchLat: 30,
    branchLng: 31,
    geofenceRadius: 100,
    isTrackingEnabled: true,
    currentStatus: status,
    currentDistanceMeters: 12,
    lastUpdated: DateTime.utc(2026, 11, 6),
    checkInTime: DateTime.utc(2026, 11, 6, 8),
  );
}

void main() {
  testWidgets('Arabic labels for extended statuses', (tester) async {
  late ColorScheme colorScheme;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          colorScheme = Theme.of(context).colorScheme;
          return const SizedBox();
        },
      ),
    ),
  );

  expect(
    TrackingGeofenceStatus.resolve(_base(TrackingStatus.forgotSignature), colorScheme)
        .title,
    'نسيان توقيع',
  );
  expect(
    TrackingGeofenceStatus.resolve(_base(TrackingStatus.suspended), colorScheme)
        .title,
    'موقوف',
  );
  expect(
    TrackingGeofenceStatus.resolve(_base(TrackingStatus.checkedOut), colorScheme)
        .title,
    'منصرف',
  );
  });
}