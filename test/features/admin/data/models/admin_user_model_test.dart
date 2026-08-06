import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot {}

void main() {
  final tDateTime = DateTime(2023, 1, 1);
  final tTimestamp = Timestamp.fromDate(tDateTime);

  final tAdminUserModel = AdminUserModel(
    uid: '123',
    phoneNumber: '123456789',
    email: 'test@test.com',
    displayName: 'Test Admin',
    role: 'company-admin',
    organizationUID: 'org1',
    companyUID: 'comp1',
    createdAt: tDateTime,
    createdBy: 'admin1',
    temporaryPassword: 'temp',
    isActive: true,
  );

  test('should be a subclass of AdminUser entity', () {
    expect(tAdminUserModel, isA<AdminUser>());
  });

  group('fromFirestore', () {
    test('should return a valid model when JSON is correct', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('123');
      when(() => mockDoc.data()).thenReturn({
        'phoneNumber': '123456789',
        'email': 'test@test.com',
        'displayName': 'Test Admin',
        'role': 'company-admin',
        'organizationUID': 'org1',
        'companyUID': 'comp1',
        'createdAt': tTimestamp,
        'createdBy': 'admin1',
        'password': 'temp',
        'isActive': true,
      });

      final result = AdminUserModel.fromFirestore(mockDoc);
      expect(result, tAdminUserModel);
    });
  });

  group('toMap', () {
    test('should return a JSON map containing the proper data', () {
      final result = tAdminUserModel.toMap();
      final expectedMap = {
        'phoneNumber': '123456789',
        'email': 'test@test.com',
        'displayName': 'Test Admin',
        'role': 'company-admin',
        'organizationUID': 'org1',
        'companyUID': 'comp1',
        'password': 'temp',
        'isActive': true,
        'createdAt': tTimestamp,
        'createdBy': 'admin1',
      };
      expect(result, expectedMap);
    });
  });
}
