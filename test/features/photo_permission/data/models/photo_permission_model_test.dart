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

  group('toJson / fromJson / fromEntity', () {
    test('should round-trip through toJson and fromJson for SharedPreferences cache', () {
      final jsonMap = tModel.toJson();
      final restored = PhotoPermissionModel.fromJson(jsonMap);

      expect(restored.uid, equals(tModel.uid));
      expect(restored.organizationUID, equals(tModel.organizationUID));
      expect(restored.companyUID, equals(tModel.companyUID));
      expect(restored.companyName, equals(tModel.companyName));
      expect(restored.companyCode, equals(tModel.companyCode));
      expect(restored.branchIds, equals(tModel.branchIds));
      expect(restored.branchNames, equals(tModel.branchNames));
      expect(restored.startDate, equals(tModel.startDate));
      expect(restored.endDate, equals(tModel.endDate));
      expect(restored.status, equals(tModel.status));
      expect(restored.requestedBy, equals(tModel.requestedBy));
      expect(restored.approvedBy, equals(tModel.approvedBy));
      expect(restored.isSupervisorEnabled, equals(tModel.isSupervisorEnabled));
    });

    test('fromEntity should preserve all entity fields', () {
      final entity = PhotoPermission(
        uid: 'entity_1',
        organizationUID: 'org_1',
        companyUID: 'comp_1',
        companyName: 'Comp 1',
        companyCode: 45,
        branchIds: const ['b1', 'b2'],
        branchNames: const ['Branch 1', 'Branch 2'],
        startDate: tDate,
        endDate: tDate,
        status: 'approved',
        requestedBy: 'req_1',
        approvedBy: 'app_1',
        department: 'Grocery',
        createdAt: tDate,
        updatedAt: tDate,
        isSupervisorEnabled: false,
      );

      final model = PhotoPermissionModel.fromEntity(entity);
      expect(model.uid, equals('entity_1'));
      expect(model.department, equals('Grocery'));
      expect(model.isSupervisorEnabled, isFalse);
    });
  });
}
