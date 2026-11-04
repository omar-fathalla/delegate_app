import 'package:cloud_functions/cloud_functions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AdminRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = AdminRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  group('BranchesSessionCache invalidation', () {
    setUp(() {
      BranchesSessionCache.invalidate();
      BranchesSessionCache.debugSessionKey = () => 'u1';
    });
    tearDown(() {
      BranchesSessionCache.invalidate();
      BranchesSessionCache.debugSessionKey = null;
    });

    test('addBranch refreshes the cached branches list', () async {
      expect(await BranchesSessionCache.load(fakeFirestore), isEmpty);
      await dataSource.addBranch(BranchModel(
          id: '', branchName: 'فرع جديد', latitude: 30, longitude: 31, geofenceRadius: 100));
      final after = await BranchesSessionCache.load(fakeFirestore);
      expect(after.map((d) => d['branchName']), contains('فرع جديد'));
    });

    test('deleteBranch refreshes the cached branches list', () async {
      await fakeFirestore.collection('branches').doc('b1').set({'branchName': 'قديم', 'organizationUID': 'o1'});
      await fakeFirestore.collection('organizations').doc('o1').collection('branches').doc('b1').set({'branchName': 'قديم'});
      expect(await BranchesSessionCache.load(fakeFirestore), hasLength(1));
      await dataSource.deleteBranch('b1');
      expect(await BranchesSessionCache.load(fakeFirestore), isEmpty);
    });

    test('deleteBranch of a branch without org also refreshes the cache', () async {
      await fakeFirestore.collection('branches').doc('b2').set({'branchName': 'بدون منظمة'});
      expect(await BranchesSessionCache.load(fakeFirestore), hasLength(1));
      await dataSource.deleteBranch('b2');
      expect(await BranchesSessionCache.load(fakeFirestore), isEmpty);
    });

    test('updateBranch refreshes the cached branches list', () async {
      await fakeFirestore.collection('branches').doc('b1').set({'branchName': 'قديم'});
      expect((await BranchesSessionCache.load(fakeFirestore)).single['branchName'], 'قديم');
      await dataSource.updateBranch(BranchModel(
          id: 'b1', branchName: 'جديد', latitude: 30, longitude: 31, geofenceRadius: 100));
      expect((await BranchesSessionCache.load(fakeFirestore)).single['branchName'], 'جديد');
    });
  });

  group('getBranches', () {
    test('should return list of branches from Firestore', () async {
      await fakeFirestore.collection('branches').doc('b1').set({
        'branchName': 'الفرع الرئيسي',
        'location': {'latitude': 30.0444, 'longitude': 31.2357},
        'geofenceRadius': 200.0,
      });
      await fakeFirestore.collection('branches').doc('b2').set({
        'branchName': 'فرع المعادي',
        'location': {'latitude': 29.96, 'longitude': 31.25},
        'geofenceRadius': 150.0,
      });

      final result = await dataSource.getBranches();

      expect(result.length, 2);
      expect(result.first.branchName, 'الفرع الرئيسي');
      expect(result.first.latitude, 30.0444);
    });

    test('should return empty list when no branches exist', () async {
      final result = await dataSource.getBranches();
      expect(result, isEmpty);
    });
  });

  group('addBranch', () {
    test('should add branch and return model with generated id', () async {
      const branch = BranchModel(
        id: '',
        branchName: 'فرع جديد',
        latitude: 30.1,
        longitude: 31.3,
        geofenceRadius: 100.0,
      );

      final result = await dataSource.addBranch(branch);

      expect(result.id, isNotEmpty);
      expect(result.branchName, 'فرع جديد');
      expect(result.latitude, 30.1);

      // Verify Firestore state
      final doc = await fakeFirestore
          .collection('branches')
          .doc(result.id)
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['branchName'], 'فرع جديد');
    });
  });

  group('updateBranch', () {
    test('should update branch data in Firestore', () async {
      await fakeFirestore.collection('branches').doc('b1').set({
        'branchName': 'الفرع القديم',
        'location': {'latitude': 30.0, 'longitude': 31.0},
        'geofenceRadius': 100.0,
      });

      const updatedBranch = BranchModel(
        id: 'b1',
        branchName: 'الفرع المحدّث',
        latitude: 30.5,
        longitude: 31.5,
        geofenceRadius: 250.0,
      );

      final result = await dataSource.updateBranch(updatedBranch);

      expect(result.branchName, 'الفرع المحدّث');

      // Verify Firestore state
      final doc = await fakeFirestore.collection('branches').doc('b1').get();
      expect(doc.data()!['branchName'], 'الفرع المحدّث');
    });
  });

  group('deleteBranch', () {
    test('should remove branch from Firestore', () async {
      await fakeFirestore.collection('branches').doc('b1').set({
        'branchName': 'فرع للحذف',
        'location': {'latitude': 30.0, 'longitude': 31.0},
        'geofenceRadius': 100.0,
      });

      await dataSource.deleteBranch('b1');

      final doc = await fakeFirestore.collection('branches').doc('b1').get();
      expect(doc.exists, false);
    });
  });

  group('createAdmin', () {
    test('calls createStaffUser with no password and writes nothing client-side', () async {
      final functions = _MockFunctions();
      final callable = _MockCallable();
      final result = _MockResult();
      Map<String, dynamic>? sent;
      when(() => functions.httpsCallable('createStaffUser')).thenReturn(callable);
      when(() => result.data).thenReturn({'uid': 'new-uid'});
      when(() => callable.call<Map<String, dynamic>>(any())).thenAnswer((inv) async {
        sent = Map<String, dynamic>.from(inv.positionalArguments.first as Map);
        return result;
      });
      final ds = AdminRemoteDataSourceImpl(firestore: fakeFirestore, functions: functions);
      final admin = AdminUserModel(
        uid: '',
        phoneNumber: '01000000000',
        email: 'test@test.com',
        displayName: 'Test',
        role: 'company-admin',
        organizationUID: 'o1',
        companyUID: 'c1',
        createdAt: DateTime.now(),
        createdBy: 'admin',
        temporaryPassword: '',
      );

      final created = await ds.createAdmin(admin);
      expect(created.uid, 'new-uid');
      expect(sent!['email'], 'test@test.com');
      expect(sent!.keys.any((k) => k.toLowerCase().contains('password')), isFalse);
      expect((await fakeFirestore.collection('users').get()).docs, isEmpty);
      expect((await fakeFirestore.collection('mail').get()).docs, isEmpty);
    });
  });

  group('getAdmins', () {
    test('should return list of admins', () async {
      await fakeFirestore.collection('users').add({
        'role': 'company-admin',
        'email': 'admin@test.com',
        'displayName': 'Admin 1',
      });
      await fakeFirestore.collection('users').add({
        'role': 'user',
        'email': 'user@test.com',
      });

      final result = await dataSource.getAdmins();
      expect(result.length, 1);
      expect(result.first.email, 'admin@test.com');
    });
  });
}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}
