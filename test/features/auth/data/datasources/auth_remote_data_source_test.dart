import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmailPasswordAuth extends MockFirebaseAuth {
  _EmailPasswordAuth({required this.acceptedPassword});

  final String acceptedPassword;
  final List<String> emails = [];
  final List<String> passwords = [];

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    emails.add(email);
    passwords.add(password);
    if (password != acceptedPassword) {
      throw FirebaseAuthException(code: 'wrong-password');
    }
    return super.signInWithEmailAndPassword(email: email, password: password);
  }
}

class _NoAnonymousAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInAnonymously() {
    throw StateError('delegate login must not sign in anonymously');
  }
}

class _FakeStaffLookup implements StaffPhoneLookupApi {
  _FakeStaffLookup(this.profile, {this.error});

  final StaffPhoneProfile? profile;
  final StaffPhoneLookupException? error;

  @override
  Future<StaffPhoneProfile?> lookup(String phone) async {
    final failure = error;
    if (failure != null) throw failure;
    return profile;
  }
}

class _FakeDelegateLoginApi implements DelegateLoginApi {
  _FakeDelegateLoginApi(this.response, {this.error});

  final DelegateLoginResponse response;
  final DelegateLoginException? error;
  int calls = 0;
  String? phone;
  String? nationalId;
  String? deviceId;

  @override
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
    required String deviceId,
    String deviceModel = '',
    String legacyDeviceId = '',
  }) async {
    calls++;
    this.phone = phone;
    this.nationalId = nationalId;
    this.deviceId = deviceId;
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
    test('ignores delegates collectionGroup documents', () async {
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

      expect(result, isEmpty);
    });

    test('uses staffPhoneLookup and does not need a users document', () async {
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: mockFirebaseAuth,
        staffPhoneLookupApi: _FakeStaffLookup(
          const StaffPhoneProfile(
            uid: 'auth-uid',
            email: 'omar@example.com',
            role: 'super_admin',
            displayName: 'Omar Fathalla',
            phoneNumber: '01508899965',
            organizationUID: 'org-1',
            companyUID: 'comp-1',
          ),
        ),
      );

      final result = await source.getDelegatesByPhone('01508899965');

      expect(result, hasLength(1));
      expect(result.first.uid, 'auth-uid');
      expect(result.first.role, UserRole.superAdmin);
      expect(result.first.email, 'omar@example.com');
      expect(result.first.nationalityID, '__firebase_auth__:omar@example.com');
    });

    test('TAS-314: email-only lookup gives a placeholder with no uid', () async {
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: mockFirebaseAuth,
        staffPhoneLookupApi: _FakeStaffLookup(
          const StaffPhoneProfile(email: 'omar@example.com'),
        ),
      );

      final result = await source.getDelegatesByPhone('01508899965');

      expect(result, hasLength(1));
      expect(result.first.uid, isEmpty);
      expect(result.first.organizationUID, isEmpty);
      expect(result.first.nationalityID, '__firebase_auth__:omar@example.com');
      expect(
        const StaffPhoneProfile(email: 'omar@example.com').isComplete,
        isFalse,
      );
    });

    test('falls back to users when staffPhoneLookup is not deployed', () async {
      await fakeFirestore.collection('users').doc('staff-1').set({
        'role': 'hr',
        'email': 'hr@example.com',
        'displayName': 'HR',
        'phoneNumber': '01000000000',
        'organizationUID': 'org1',
        'companyUID': 'comp1',
      });
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: mockFirebaseAuth,
        staffPhoneLookupApi: _FakeStaffLookup(
          null,
          error: const StaffPhoneLookupException('unavailable'),
        ),
      );

      final result = await source.getDelegatesByPhone('01000000000');

      expect(result, hasLength(1));
      expect(result.first.role, UserRole.hr);
      expect(result.first.email, 'hr@example.com');
    });

    test('does not fall back to users when the callable says not found', () async {
      await fakeFirestore.collection('users').doc('staff-1').set({
        'role': 'hr',
        'email': 'hr@example.com',
        'phoneNumber': '01000000000',
      });
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: mockFirebaseAuth,
        staffPhoneLookupApi: _FakeStaffLookup(null),
      );

      final result = await source.getDelegatesByPhone('01000000000');

      expect(result, isEmpty);
    });

    test('should return empty list when phone number is not found', () async {
      final result = await dataSource.getDelegatesByPhone('09999999999');

      expect(result, isEmpty);
    });

    test('should normalize phone number with +20 prefix against users', () async {
      await fakeFirestore.collection('users').doc('staff-sara').set({
        'phoneNumber': '01234567890',
        'role': 'company-admin',
        'email': 'sara@example.com',
        'displayName': 'سارة',
      });

      final result = await dataSource.getDelegatesByPhone('+201234567890');

      expect(result, isNotEmpty);
      expect(result.first.firstName, 'سارة');
      expect(result.first.email, 'sara@example.com');
    });

    test('should find admin in users collection without anonymous sign-in', () async {
      await fakeFirestore
          .collection('organizations')
          .doc('org1')
          .collection('companies')
          .doc('comp1')
          .collection('delegates')
          .doc('same-phone')
          .set({
            'firstName': 'مندوب',
            'phoneNumber': '01500000000',
            'nationalityID': '11111111111111',
            'status': 'active',
          });
      await fakeFirestore.collection('users').doc('admin1').set({
        'phoneNumber': '01500000000',
        'role': 'company-admin',
        'email': 'admin@example.com',
        'displayName': 'مدير',
        'organizationUID': 'org1',
        'organizationName': 'منظمة تسهيل',
        'companyUID': 'comp1',
        'companyName': 'شركة تسهيل',
      });
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: _NoAnonymousAuth(),
      );

      final result = await source.getDelegatesByPhone('01500000000');

      expect(result, isNotEmpty);
      expect(result.first.position, DelegatePosition.supervisor);
      expect(result.first.email, 'admin@example.com');
      expect(
        result.first.nationalityID,
        '__firebase_auth__:admin@example.com',
      );
    });

    test('loads a super-admin user from the real document', () async {
      await fakeFirestore.collection('users').doc('auth-uid').set({
        'phoneNumber': '01500000001',
        'role': 'super-admin',
        'email': 'super@example.com',
        'displayName': 'Omar Fathalla',
        'organizationUID': 'org-real',
        'organizationName': 'Org',
      });

      final result = await dataSource.getDelegatesByPhone('01500000001');

      expect(result, hasLength(1));
      expect(result.single.uid, 'auth-uid');
      expect(result.single.role, UserRole.superAdmin);
      expect(result.single.email, 'super@example.com');
      expect(result.single.organizationUID, 'org-real');
      expect(
        result.single.nationalityID,
        '__firebase_auth__:super@example.com',
      );
    });

    test('still reads a legacy super_admin role string', () async {
      await fakeFirestore.collection('users').doc('legacy').set({
        'phoneNumber': '01500000002',
        'role': 'super_admin',
        'email': 'legacy@example.com',
        'displayName': 'Legacy',
      });

      final result = await dataSource.getDelegatesByPhone('01500000002');

      expect(result.single.role, UserRole.superAdmin);
    });

    test('does not invent a staff account when the phone has no document', () async {
      final result = await dataSource.getDelegatesByPhone('01500000099');
      expect(result, isEmpty);
    });
  });

  group('staff password login', () {
    test('signs in with the email looked up from the phone', () async {
      await fakeFirestore.collection('users').doc('auth-uid').set({
        'phoneNumber': '01500000001',
        'role': 'super-admin',
        'email': 'super@example.com',
        'password': 'stored-in-firestore',
      });
      final auth = _EmailPasswordAuth(acceptedPassword: 'auth-secret');
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
      );

      final signedIn = await source.verifyPhonePassword(
        '01500000001',
        'auth-secret',
      );

      expect(signedIn, isTrue);
      expect(auth.emails, ['super@example.com']);
      expect(auth.passwords, ['auth-secret']);
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.isAnonymous, isFalse);
    });

    test('a wrong password fails even when Firestore stores that password', () async {
      await fakeFirestore.collection('users').doc('auth-uid').set({
        'phoneNumber': '01500000001',
        'role': 'super-admin',
        'email': 'super@example.com',
        'password': 'stored-in-firestore',
      });
      final auth = _EmailPasswordAuth(acceptedPassword: 'auth-secret');
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
      );

      final stored = await source.verifyPhonePassword(
        '01500000001',
        'stored-in-firestore',
      );
      final wrong = await source.verifyAdminPassword(
        'super@example.com',
        'wrong-password',
      );

      expect(stored, isFalse);
      expect(wrong, isFalse);
      expect(auth.currentUser, isNull);
      expect(auth.emails, ['super@example.com', 'super@example.com']);
    });

    test('does not sign in when the user document has no email', () async {
      await fakeFirestore.collection('users').doc('auth-uid').set({
        'phoneNumber': '01500000001',
        'role': 'super-admin',
        'displayName': 'Omar Fathalla',
      });
      final auth = _EmailPasswordAuth(acceptedPassword: 'auth-secret');
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
      );

      final signedIn = await source.verifyPhonePassword(
        '01500000001',
        'auth-secret',
      );

      expect(signedIn, isFalse);
      expect(auth.emails, isEmpty);
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
        currentDeviceDetails: () async => {
          'deviceId': 'install-device-1',
          'deviceModel': 'Test Phone',
        },
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
      expect(api.deviceId, 'install-device-1');
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
        currentDeviceDetails: () async => {'deviceId': 'install-device-1'},
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

    test('does not sign in when the server rejects the device', () async {
      final auth = _NoAnonymousAuth();
      final api = _FakeDelegateLoginApi(
        const DelegateLoginResponse(token: 'unused', delegateIds: []),
        error: const DelegateLoginException('device_mismatch'),
      );
      final source = AuthRemoteDataSourceImpl(
        firestore: fakeFirestore,
        firebaseAuth: auth,
        delegateLoginApi: api,
        currentDeviceDetails: () async => {'deviceId': 'other-phone'},
      );

      expect(
        () => source.loginDelegate(
          phoneNumber: '01000000000',
          nationalId: '12345678901234',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            'device_mismatch',
          ),
        ),
      );
      expect(auth.currentUser, isNull);
    });
  });
}
