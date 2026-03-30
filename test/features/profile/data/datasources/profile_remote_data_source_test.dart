import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProfileRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = ProfileRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  Future<void> seedDelegateData({
    String uid = 'u1',
    String role = 'delegate',
    String orgId = 'org1',
    String companyId = 'comp1',
  }) async {
    // Seed user record
    await fakeFirestore.collection('users').doc(uid).set({
      'role': role,
      'organizationUID': orgId,
      'companyUID': companyId,
    });

    // Seed delegate record
    await fakeFirestore
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(companyId)
        .collection('delegates')
        .doc(uid)
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
          'status': 'active',
          'organizationUID': orgId,
          'companyUID': companyId,
        });
  }

  group('getDelegateProfile', () {
    test('should return DelegateModel when delegate exists', () async {
      await seedDelegateData();

      final result = await dataSource.getDelegateProfile('u1');

      expect(result.firstName, 'أحمد');
      expect(result.phoneNumber, '01000000000');
      expect(result.nationalityID, '12345678901234');
    });

    test('should throw ServerException when user not found', () async {
      expect(
        () => dataSource.getDelegateProfile('nonexistent'),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when user is not a delegate', () async {
      await fakeFirestore.collection('users').doc('admin1').set({
        'role': 'company-admin',
        'organizationUID': 'org1',
        'companyUID': 'comp1',
      });

      expect(
        () => dataSource.getDelegateProfile('admin1'),
        throwsA(isA<ServerException>()),
      );
    });

    test(
      'should throw ServerException when org/company IDs are missing',
      () async {
        await fakeFirestore.collection('users').doc('u2').set({
          'role': 'delegate',
        });

        expect(
          () => dataSource.getDelegateProfile('u2'),
          throwsA(isA<ServerException>()),
        );
      },
    );
  });
}
