import 'package:delegate_app/features/tracking/data/models/delegate_tracking_session_model.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-71: fake-GPS alerts must reach the company's supervisors without the
/// delegate listing `users`, and the audit log must carry the fields the
/// rules require (`delegateUid` == auth uid, company/org ids).
void main() {
  late FakeFirebaseFirestore db;
  late DelegateTrackingService service;

  DelegateTrackingSessionModel session({bool trackingEnabled = false}) =>
      DelegateTrackingSessionModel(
        delegateId: 'del_1',
        delegateName: 'أحمد',
        delegatePhone: '01000000000',
        companyId: 'comp_1',
        organizationId: 'org_1',
        branchId: 'br_1',
        branchName: 'فرع المعادي',
        branchLat: 30.0,
        branchLng: 31.0,
        geofenceRadius: 100,
        isTrackingEnabled: trackingEnabled,
        currentStatus: TrackingStatus.insideZone,
        currentDistanceMeters: 0,
        lastUpdated: DateTime(2026, 11, 22, 10),
        isOnline: true,
        isMockLocationDetected: false,
        offlineBreadcrumbsCount: 0,
      );

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = DelegateTrackingService(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'auth_del_1'),
      ),
    );
    await db.collection('delegate_tracking').doc('del_1').set(session().toJson());
  });

  test('mock location writes one supervisor broadcast with createdBy and company', () async {
    await service.updateLocationAndCheckGeofence(
      delegateId: 'del_1',
      currentLat: 30.0,
      currentLng: 31.0,
      isMocked: true,
    );

    final notifs = await db.collection('notifications').get();
    expect(notifs.docs, hasLength(1), reason: 'exactly one broadcast, no per-user fan-out');
    final n = notifs.docs.single.data();
    expect(n['delegateUid'], 'supervisor_comp_1');
    expect(n['createdBy'], 'auth_del_1');
    expect(n['companyUID'], 'comp_1');
    expect(n['companyId'], 'comp_1');
    expect(n['organizationUID'], 'org_1');
    expect(n['type'], 'mock_location_alert');
    expect(n['targetDelegateId'], 'del_1');

    // No `users` reads were needed for the alert.
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  test('mock location audit log carries delegateUid, companyUID and organizationUID', () async {
    await service.updateLocationAndCheckGeofence(
      delegateId: 'del_1',
      currentLat: 30.0,
      currentLng: 31.0,
      isMocked: true,
    );

    final logs = await db.collection('security_audit_logs').get();
    expect(logs.docs, hasLength(1));
    final log = logs.docs.single.data();
    expect(log['action'], 'mock_location_detected_during_tracking');
    expect(log['delegateUid'], 'auth_del_1');
    expect(log['delegateId'], 'del_1');
    expect(log['companyUID'], 'comp_1');
    expect(log['organizationUID'], 'org_1');

    final tracking = await db.collection('delegate_tracking').doc('del_1').get();
    expect(tracking.data()!['isMockLocationDetected'], isTrue);
  });

  test('falls back to the session delegate id when nobody is signed in', () async {
    service = DelegateTrackingService(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: false),
    );
    await service.updateLocationAndCheckGeofence(
      delegateId: 'del_1',
      currentLat: 30.0,
      currentLng: 31.0,
      isMocked: true,
    );
    final n = (await db.collection('notifications').get()).docs.single.data();
    expect(n['createdBy'], 'del_1');
  });

  test('a session without a company sends no alert and does not throw', () async {
    final noCompany = session().toJson()..['companyId'] = '';
    await db.collection('delegate_tracking').doc('del_1').set(noCompany);

    await service.updateLocationAndCheckGeofence(
      delegateId: 'del_1',
      currentLat: 30.0,
      currentLng: 31.0,
      isMocked: true,
    );

    expect((await db.collection('notifications').get()).docs, isEmpty);
  });
}
