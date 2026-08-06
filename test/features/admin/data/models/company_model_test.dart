import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/models/company_model.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot {}

void main() {
  final tDateTime = DateTime(2023, 1, 1);
  final tTimestamp = Timestamp.fromDate(tDateTime);

  final tCompanyModel = CompanyModel(
    uid: '123',
    name: 'Test Company',
    companyCodeInOrg: '1234',
    organizationUID: 'org1',
    type: 'Retail',
    status: 'active',
    createdAt: tDateTime,
    updatedAt: tDateTime,
    admins: 1,
    delegates: 5,
    deferredPayment: true,
    description: 'A test company',
    address: '123 Test St',
    phone: '123456789',
    email: 'test@company.com',
    code: 1001,
  );

  test('should be a subclass of Company entity', () {
    expect(tCompanyModel, isA<Company>());
  });

  group('fromFirestore', () {
    test('should return a valid model when JSON is correct', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('123');
      when(() => mockDoc.data()).thenReturn({
        'name': 'Test Company',
        'companyCodeInOrg': '1234',
        'organizationUID': 'org1',
        'type': 'Retail',
        'status': 'active',
        'createdAt': tTimestamp,
        'updatedAt': tTimestamp,
        'admins': 1,
        'delegates': 5,
        'deferredPayment': true,
        'description': 'A test company',
        'address': '123 Test St',
        'phone': '123456789',
        'email': 'test@company.com',
        'code': 1001,
      });

      final result = CompanyModel.fromFirestore(mockDoc);
      expect(result, tCompanyModel);
    });
  });

  group('fromJson', () {
    test('should return a valid model when JSON is correct', () {
      final jsonMap = {
        'uid': '123',
        'name': 'Test Company',
        'companyCodeInOrg': '1234',
        'organizationUID': 'org1',
        'type': 'Retail',
        'status': 'active',
        'createdAt': tTimestamp,
        'updatedAt': tTimestamp,
        'admins': 1,
        'delegates': 5,
        'deferredPayment': true,
        'description': 'A test company',
        'address': '123 Test St',
        'phone': '123456789',
        'email': 'test@company.com',
        'code': 1001,
      };

      final result = CompanyModel.fromJson(jsonMap);
      expect(result, tCompanyModel);
    });
  });

  group('toJson', () {
    test('should return a JSON map containing the proper data', () {
      final result = tCompanyModel.toJson();
      final expectedMap = {
        'uid': '123',
        'name': 'Test Company',
        'companyCodeInOrg': '1234',
        'organizationUID': 'org1',
        'type': 'Retail',
        'status': 'active',
        'createdAt': tTimestamp,
        'updatedAt': tTimestamp,
        'admins': 1,
        'delegates': 5,
        'deferredPayment': true,
        'description': 'A test company',
        'address': '123 Test St',
        'phone': '123456789',
        'email': 'test@company.com',
        'code': 1001,
      };
      expect(result, expectedMap);
    });
  });
}
