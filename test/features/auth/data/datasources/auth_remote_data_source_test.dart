import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoAnonymousAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInAnonymously() {
    throw StateError('delegate login must not sign in anonymously');
  }
}

class _FakeDelegateLoginApi implements DelegateLoginApi {
  _FakeDelegateLoginApi(this.response, {this.error});

  final DelegateLoginResponse response;
  final DelegateLoginException? error;
  int calls = 0;
  String? phone;
  String? nationalId;

  @override
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
  }) async {
    calls++;
    this.phone = phone;
    this.nationalId = nationalId;
    final failure = error;
    if (failure != null) throw failure;
    return response;
  }
}

void main() {
  late AuthRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockFirebaseAuth;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockFirebaseAuth = MockFirebaseAuth();
    dataSource = AuthRemoteDataSourceImpl(
      firestore: fakeFirestore,
      firebaseAuth: mockFirebaseAuth,
    );
  });

  group('getDelegatesByPhone', () {
    test(
      'should return list of DelegateModels when delegate found in collectionGroup',
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

        final result = await dataSource.getDelegatesByPhone('01000000000');

        expect(result, isNotEmpty);
        expect(result.first.firstName, 'أحمد');
        expect(result.first.phoneNumber, '01000000000');
        expect(result.first.nationalityID, '12345678901234');
      },
    );

    test('should return empty list when phone number is not found', () async {
      final result = await dataSource.getDelegatesByPhone('09999999999');

      expect(result, isEmpty);
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

      final result = await dataSource.getDelegatesByPhone('+201234567890');

      expect(result, isNotEmpty);
      expect(result.first.firstName, 'سارة');
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

      final result = await dataSource.getDelegatesByPhone('01508899965');

      expect(result, isNotEmpty);
      expect(result.first.position, DelegatePosition.supervisor);
    });
  });

  group('loginDelegate', () {
    test('signs in with the custom token and returns only authorized profiles', () async {
      final auth = _NoAnonymousAuth();
      final api = _FakeDelegateLoginApi(
        const DelegateLoginResponse(token: 'custom-token', delegateIds: ['d1']),
      );
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
        delegateLoginApi: api,
      );
      await fakeFirestore
          .collection('organizations')
          .doc('org1')
          .collection('companies')
          .doc('comp1')
          .collection('delegates')
          .doc('d1')
          .set({
            'firstName': 'أحمد',
            'phoneNumber': '01000000000',
            'nationalityID': '12345678901234',
            'status': 'active',
          });
      await fakeFirestore
          .collection('organizations')
          .doc('org1')
          .collection('companies')
          .doc('comp1')
          .collection('delegates')
          .doc('other')
          .set({
            'firstName': 'غير مصرح',
            'phoneNumber': '01000000000',
            'nationalityID': '99999999999999',
            'status': 'active',
          });

      final result = await source.loginDelegate(
        phoneNumber: '+201000000000',
        nationalId: '12345678901234',
      );

      expect(api.calls, 1);
      expect(api.nationalId, '12345678901234');
      expect(result, hasLength(1));
      expect(result.single.uid, 'd1');
      expect(result.single.firstName, 'أحمد');
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.isAnonymous, isFalse);
    });

    test('does not sign in anonymously when the national ID is rejected', () async {
      final auth = _NoAnonymousAuth();
      final api = _FakeDelegateLoginApi(
        const DelegateLoginResponse(token: 'unused', delegateIds: []),
        error: const DelegateLoginException('bad_credentials'),
      );
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
        delegateLoginApi: api,
      );

      expect(
        () => source.loginDelegate(
          phoneNumber: '01000000000',
          nationalId: '00000000000000',
        ),
        throwsA(isA<DelegateCredentialsFailure>()),
      );
      expect(auth.currentUser, isNull);
    });
  });
}
