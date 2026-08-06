import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ignore: subtype_of_sealed_class
class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  final tDate = DateTime(2023, 1, 1);
  final tModel = CapturedPhotoModel(
    uid: 'test_uid',
    permissionId: 'perm_1',
    organizationUID: 'org_1',
    companyUID: 'company_1',
    branchId: 'branch_1',
    branchName: 'Branch 1',
    delegateUID: 'del_1',
    delegateName: 'Delegate 1',
    photoUrl: 'https://example.com/photo.jpg',
    comment: 'Test Comment',
    latitude: 30.0,
    longitude: 31.0,
    capturedAt: tDate,
  );

  test('should be a subclass of CapturedPhoto entity', () {
    expect(tModel, isA<CapturedPhoto>());
  });

  group('fromFirestore', () {
    test('should return a valid model when creating from Firestore', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('test_uid');
      when(() => mockDoc.data()).thenReturn({
        'permissionId': 'perm_1',
        'organizationUID': 'org_1',
        'companyUID': 'company_1',
        'branchId': 'branch_1',
        'branchName': 'Branch 1',
        'delegateUID': 'del_1',
        'delegateName': 'Delegate 1',
        'photoUrl': 'https://example.com/photo.jpg',
        'comment': 'Test Comment',
        'location': const GeoPoint(30.0, 31.0),
        'capturedAt': Timestamp.fromDate(tDate),
      });

      final result = CapturedPhotoModel.fromFirestore(mockDoc);

      expect(result.uid, equals(tModel.uid));
      expect(result.branchName, equals(tModel.branchName));
      expect(result.latitude, equals(tModel.latitude));
      expect(result.longitude, equals(tModel.longitude));
      expect(result.capturedAt, equals(tModel.capturedAt));
    });

    test('should handle missing fields', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('test_uid');
      when(() => mockDoc.data()).thenReturn({});

      final result = CapturedPhotoModel.fromFirestore(mockDoc);

      expect(result.uid, equals('test_uid'));
      expect(result.branchName, equals(''));
      expect(result.latitude, equals(0.0));
      expect(result.longitude, equals(0.0));
    });
  });

  group('toFirestore', () {
    test('should return a map containing the proper data', () {
      final result = tModel.toFirestore();

      expect(result['organizationUID'], equals('org_1'));
      expect(result['location'], isA<GeoPoint>());
      expect((result['location'] as GeoPoint).latitude, equals(30.0));
      expect(result['capturedAt'], isA<Timestamp>());
    });
  });
}
