import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AuthRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = AuthRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  group('getDelegateByPhone', () {
    test('should return DelegateModel when delegate found in collectionGroup',
        () async {
      // Seed data in the nested delegates collection
      await fakeFirestore
          .collection('organizations')
          .doc('org1')
          .collection('companies')
          .doc('comp1')
          .collection('delegates')
          .doc('d1')
          .set({
        'firstName': 'أحمد',
        'middleName': 'محمد',
        'lastName': 'علي',
        'fullName': 'أحمد محمد علي',
        'nationalityID': '12345678901234',
        'motherName': 'منى',
        'city': 'القاهرة',
        'phoneNumber': '01000000000',
        'gender': 'male',
        'position': 'promoter',
        'birthDate': '1995-01-01',
        'organizationUID': 'org1',
        'organizationName': 'منظمة تسهيل',
        'companyUID': 'comp1',
        'companyName': 'شركة تسهيل',
        'status': 'active',
        'delegatePublicId': 'DEL-001',
        'createdBy': 'admin',
      });

      final result = await dataSource.getDelegateByPhone('01000000000');

      expect(result, isNotNull);
      expect(result!.firstName, 'أحمد');
      expect(result.phoneNumber, '01000000000');
      expect(result.nationalityID, '12345678901234');
    });

    test('should return null when phone number is not found', () async {
      final result = await dataSource.getDelegateByPhone('09999999999');

      expect(result, isNull);
    });

    test('should normalize phone number with +20 prefix', () async {
      await fakeFirestore
          .collection('organizations')
          .doc('org1')
          .collection('companies')
          .doc('comp1')
          .collection('delegates')
          .doc('d2')
          .set({
        'firstName': 'سارة',
        'phoneNumber': '01234567890',
        'gender': 'female',
        'position': 'promoter',
        'status': 'active',
      });

      final result = await dataSource.getDelegateByPhone('+201234567890');

      expect(result, isNotNull);
      expect(result!.firstName, 'سارة');
    });

    test('should find admin in users collection', () async {
      await fakeFirestore.collection('users').doc('admin1').set({
        'phoneNumber': '01508899965',
        'role': 'company-admin',
        'displayName': 'مدير',
        'organizationUID': 'org1',
        'organizationName': 'منظمة تسهيل',
        'companyUID': 'comp1',
        'companyName': 'شركة تسهيل',
      });

      final result = await dataSource.getDelegateByPhone('01508899965');

      expect(result, isNotNull);
      expect(result!.position, DelegatePosition.supervisor);
    });
  });
}
