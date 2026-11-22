import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-77: a captured photo stores the server's capture time.
void main() {
  final deviceTime = DateTime(2026, 11, 22, 9, 30);
  final model = CapturedPhotoModel(
    uid: 'ph1',
    permissionId: 'p1',
    organizationUID: 'org_a',
    companyUID: 'co_1',
    branchId: 'b1',
    branchName: 'Fake branch',
    delegateUID: 'd1',
    delegateName: 'Fake',
    photoUrl: 'https://cdn.example/x.jpg',
    comment: '',
    latitude: 30,
    longitude: 31,
    capturedAt: deviceTime,
  );

  test('capturedAt is a server timestamp, the device time is kept apart', () {
    final data = capturedPhotoWriteData(model);
    expect(data['capturedAt'], FieldValue.serverTimestamp());
    expect(data['deviceCapturedAt'], Timestamp.fromDate(deviceTime));
  });

  test('everything else is the model as before', () {
    final data = capturedPhotoWriteData(model);
    final plain = model.toFirestore();
    for (final key in plain.keys.where((k) => k != 'capturedAt')) {
      expect(data[key], plain[key], reason: key);
    }
    expect(data['monthKey'], '2026-11');
  });
}
