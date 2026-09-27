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

    test('should parse delegate data with fullName, phone, and status fallback', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('del_123');
      when(() => mockDoc.data()).thenReturn({
        'phone': '01012345678',
        'fullName': 'Mohamed Ali',
        'role': 'delegate',
        'organizationId': 'org_alpha',
        'organizationName': 'Alpha Org',
        'status': 'Approved',
      });

      final result = AdminUserModel.fromFirestore(mockDoc);
      expect(result.uid, 'del_123');
      expect(result.displayName, 'Mohamed Ali');
      expect(result.phoneNumber, '01012345678');
      expect(result.role, 'delegate');
      expect(result.organizationUID, 'org_alpha');
      expect(result.organizationName, 'Alpha Org');
      expect(result.isActive, true);
    });

    test('should infer supervisor role when position is supervisor', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('sup_123');
      when(() => mockDoc.data()).thenReturn({
        'name': 'Supervisor Sami',
        'position': 'supervisor',
        'status': 'suspended',
      });

      final result = AdminUserModel.fromFirestore(mockDoc);
      expect(result.uid, 'sup_123');
      expect(result.displayName, 'Supervisor Sami');
      expect(result.role, 'supervisor');
      expect(result.isActive, false);
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

    test('should include companyName and jobTitle when present', () {
      final hrAdmin = AdminUserModel(
        uid: 'hr1',
        phoneNumber: '01012345678',
        email: 'hr@company.com',
        displayName: 'HR Manager',
        role: 'hr',
        organizationUID: 'org1',
        companyUID: 'comp1',
        companyName: 'Al-Amal Co',
        jobTitle: 'HR Specialist',
        createdAt: tDateTime,
        createdBy: 'admin1',
        temporaryPassword: 'temp',
        isActive: true,
      );

      final result = hrAdmin.toMap();
      expect(result['companyName'], 'Al-Amal Co');
      expect(result['jobTitle'], 'HR Specialist');
      expect(result['role'], 'hr');
    });
  });
}
