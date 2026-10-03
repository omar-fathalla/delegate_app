import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/data/models/delegate_tracking_session_model.dart';

void main() {
  group('DelegateTrackingSessionModel', () {
    final now = DateTime(2026, 9, 25, 10, 30);

    final testModel = DelegateTrackingSessionModel(
      delegateId: 'del_123',
      delegateName: 'أحمد محمود',
      delegatePhone: '01012345678',
      companyId: 'comp_1',
      organizationId: 'org_1',
      branchId: 'branch_1',
      branchName: 'فرع المعادي',
      branchLat: 29.96,
      branchLng: 31.25,
      geofenceRadius: 150.0,
      isTrackingEnabled: true,
      currentStatus: TrackingStatus.insideZone,
      currentDistanceMeters: 45.0,
      lastLatitude: 29.9601,
      lastLongitude: 31.2501,
      lastUpdated: now,
      checkInTime: now,
      firstExitedAt: null,
      isOnline: true,
      isMockLocationDetected: false,
      offlineBreadcrumbsCount: 0,
      speed: 35.5,
      batteryLevel: 82,
      isMoving: true,
    );

    test('should be a subclass of DelegateTrackingSession entity', () {
      expect(testModel, isA<DelegateTrackingSession>());
    });

    test('should correctly serialize toJson and parse fromJson with telemetry', () {
      final json = testModel.toJson();
      expect(json['delegateId'], 'del_123');
      expect(json['delegateName'], 'أحمد محمود');
      expect(json['currentStatus'], 'inside');
      expect(json['isTrackingEnabled'], true);
      expect(json['isMockLocationDetected'], false);
      expect(json['speed'], 35.5);
      expect(json['batteryLevel'], 82);
      expect(json['isMoving'], true);

      final fromJson =
          DelegateTrackingSessionModel.fromJson(json, 'del_123');
      expect(fromJson.delegateId, 'del_123');
      expect(fromJson.delegateName, 'أحمد محمود');
      expect(fromJson.currentStatus, TrackingStatus.insideZone);
      expect(fromJson.isInside, true);
      expect(fromJson.isOutside, false);
      expect(fromJson.isOffline, false);
      expect(fromJson.isMockLocationDetected, false);
      expect(fromJson.speed, 35.5);
      expect(fromJson.batteryLevel, 82);
      expect(fromJson.isMoving, true);
    });

    test('should handle outside, offline, and mock location statuses correctly', () {
      final outsideJson = {
        'delegateId': 'del_2',
        'delegateName': 'سيد علي',
        'currentStatus': 'outside',
        'isTrackingEnabled': true,
        'isMockLocationDetected': true,
      };
      final modelOutside =
          DelegateTrackingSessionModel.fromJson(outsideJson, 'del_2');
      expect(modelOutside.currentStatus, TrackingStatus.outsideZone);
      expect(modelOutside.isOutside, true);
      expect(modelOutside.isMockLocationDetected, true);

      final offlineJson = {
        'delegateId': 'del_3',
        'delegateName': 'محمود فوزي',
        'currentStatus': 'offline',
        'isOnline': false,
      };
      final modelOffline =
          DelegateTrackingSessionModel.fromJson(offlineJson, 'del_3');
      expect(modelOffline.currentStatus, TrackingStatus.offline);
      expect(modelOffline.isOffline, true);
    });

    test('should calculate grace period accurately', () {
      final exitTime = DateTime.now().subtract(const Duration(minutes: 1));
      final graceModel = DelegateTrackingSessionModel(
        delegateId: 'del_grace',
        delegateName: 'طارق إبراهيم',
        delegatePhone: '0100000000',
        companyId: 'comp_1',
        organizationId: 'org_1',
        branchId: 'b_1',
        branchName: 'فرع الهرم',
        branchLat: 29.98,
        branchLng: 31.13,
        geofenceRadius: 100.0,
        isTrackingEnabled: true,
        currentStatus: TrackingStatus.outsideZone,
        currentDistanceMeters: 140.0,
        lastUpdated: DateTime.now(),
        firstExitedAt: exitTime,
      );

      expect(graceModel.isInGracePeriod, true);
      expect(graceModel.remainingGraceSeconds > 0, true);
      expect(graceModel.remainingGraceSeconds <= 180, true);
    });
  });
}
