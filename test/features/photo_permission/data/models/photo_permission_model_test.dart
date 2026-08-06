import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/photo_permission/data/models/photo_permission_model.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ignore: subtype_of_sealed_class
class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  final tDate = DateTime(2023, 1, 1);
  final tModel = PhotoPermissionModel(
    uid: 'test_uid',
    organizationUID: 'org_uid',
    companyUID: 'company_uid',
    companyName: 'Company',
    companyCode: 123,
    branchIds: const ['b1'],
    branchNames: const ['Branch 1'],
    startDate: tDate,
    endDate: tDate,
    status: 'pending',
    requestedBy: 'user_1',
    approvedBy: 'admin_1',
    createdAt: tDate,
    updatedAt: tDate,
    isSupervisorEnabled: true,
  );

  test('should be a subclass of PhotoPermission entity', () {
    expect(tModel, isA<PhotoPermission>());
  });

  group('fromFirestore', () {
    test('should return a valid model when creating from Firestore', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('test_uid');
      when(() => mockDoc.data()).thenReturn({
        'organizationUID': 'org_uid',
        'companyUID': 'company_uid',
        'companyName': 'Company',
        'companyCode': 123,
        'branchIds': ['b1'],
        'branchNames': ['Branch 1'],
        'startDate': Timestamp.fromDate(tDate),
        'endDate': Timestamp.fromDate(tDate),
        'status': 'pending',
        'requestedBy': 'user_1',
        'approvedBy': 'admin_1',
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
        'isSupervisorEnabled': true,
      });

      final result = PhotoPermissionModel.fromFirestore(mockDoc);

      expect(result.uid, equals(tModel.uid));
      expect(result.companyName, equals(tModel.companyName));
      expect(result.branchIds, equals(tModel.branchIds));
      expect(result.startDate, equals(tModel.startDate));
      expect(result.isSupervisorEnabled, equals(tModel.isSupervisorEnabled));
    });

    test('should handle missing fields', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('test_uid');
      when(() => mockDoc.data()).thenReturn({});

      final result = PhotoPermissionModel.fromFirestore(mockDoc);

      expect(result.uid, equals('test_uid'));
      expect(result.companyName, equals(''));
      expect(result.status, equals('pending'));
      expect(result.isSupervisorEnabled, equals(true)); // Default is true
    });
  });

  group('toFirestore', () {
    test('should return a map containing the proper data', () {
      final result = tModel.toFirestore();

      expect(result['organizationUID'], equals('org_uid'));
      expect(result['companyCode'], equals(123));
      expect(result['startDate'], isA<Timestamp>());
      expect(result['isSupervisorEnabled'], equals(true));
    });
  });
}
