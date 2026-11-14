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
    test('maps checked_out (and variants) to TrackingStatus.checkedOut, never inside', () {
      for (final raw in ['checked_out', 'checked-out', 'checkout', 'CHECKED_OUT']) {
        final model = DelegateTrackingSessionModel.fromJson({
          'delegateId': 'del_out',
          'delegateName': 'أسماء',
          'currentStatus': raw,
          'checkInTime': '2026-11-06T08:00:00.000Z',
          'checkOutTime': '2026-11-06T21:08:00.000Z',
        }, 'del_out');
        expect(model.currentStatus, TrackingStatus.checkedOut, reason: raw);
        expect(model.isInside, isFalse, reason: raw);
        expect(model.isOutside, isFalse, reason: raw);
        expect(model.checkOutTime, isNotNull, reason: raw);
      }
    });

    test('maps forgot_signature and suspended without treating as inside', () {
      for (final raw in ['forgot_signature', 'forgot-checkout', 'نسيان_توقيع']) {
        final model = DelegateTrackingSessionModel.fromJson({
          'delegateId': 'del_f',
          'currentStatus': raw,
        }, 'del_f');
        expect(model.currentStatus, TrackingStatus.forgotSignature, reason: raw);
        expect(model.isInside, isTrue, reason: raw);
      }
      final suspended = DelegateTrackingSessionModel.fromJson({
        'delegateId': 'del_s',
        'currentStatus': 'suspended',
      }, 'del_s');
      expect(suspended.currentStatus, TrackingStatus.suspended);
      expect(suspended.isInside, isFalse);
    });

    test('unknown status maps to offline, not inside', () {
      final model = DelegateTrackingSessionModel.fromJson({
        'delegateId': 'del_x',
        'currentStatus': 'weird_future_status',
      }, 'del_x');
      expect(model.currentStatus, TrackingStatus.offline);
      expect(model.isInside, isFalse);
    });

    test('toJson writes checked_out for checkedOut status', () {
      final model = DelegateTrackingSessionModel(
        delegateId: 'del_out',
        delegateName: 'أسماء',
        delegatePhone: '010',
        companyId: 'c',
        organizationId: 'o',
        branchId: 'b',
        branchName: 'فرع',
        branchLat: 30,
        branchLng: 31,
        geofenceRadius: 100,
        isTrackingEnabled: false,
        currentStatus: TrackingStatus.checkedOut,
        currentDistanceMeters: 0,
        lastUpdated: now,
        checkInTime: now,
        checkOutTime: now.add(const Duration(hours: 8)),
      );
      expect(model.toJson()['currentStatus'], 'checked_out');
    });

  });
}
