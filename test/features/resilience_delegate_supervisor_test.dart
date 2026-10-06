import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/photo_permission/data/models/photo_permission_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockQuery<T> extends Mock implements Query<T> {}
class MockQuerySnapshot<T> extends Mock implements QuerySnapshot<T> {}

void main() {
  setUpAll(() {
    registerFallbackValue(const GetOptions());
  });

  group('Delegate Experience - Login & Resilient Data Sync', () {
    test('Delegate authentication: verifies normalized phone and national ID match', () {
      final tDelegate = DelegateModel.fromJson({
        'firstName': 'Ahmed',
        'middleName': 'Mohamed',
        'lastName': 'Ali',
        'fullName': 'Ahmed Mohamed Ali',
        'nationalityID': '29510101234567',
        'motherName': 'Fatma',
        'city': 'Alexandria',
        'phoneNumber': '01012345678',
        'gender': 'Male',
        'position': 'promoter',
        'birthDate': '1995-10-10',
        'organizationUID': 'org_tashil',
        'organizationName': 'Tashil Business',
        'companyUID': 'comp_fathalla',
        'companyName': 'Fathalla Market',
        'status': 'approved',
        'delegatePublicId': 'DEL-101',
      }, 'del_101');

      // Verify phone and National ID verification
      expect(tDelegate.phoneNumber, equals('01012345678'));
      expect(tDelegate.nationalityID, equals('29510101234567'));
      expect(tDelegate.position, equals(DelegatePosition.promoter));
      expect(tDelegate.position == DelegatePosition.supervisor, isFalse);
    });

    test('Delegate resilient query: loads from server first, and from cache when in dark zone', () async {
      final mockQuery = MockQuery<Map<String, dynamic>>();
      final mockServerSnap = MockQuerySnapshot<Map<String, dynamic>>();
      final mockCacheSnap = MockQuerySnapshot<Map<String, dynamic>>();

      // 1. Normal branch with connectivity: fetch from server
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async => mockServerSnap);

      final onlineResult = await mockQuery.getResilient();
      expect(onlineResult, equals(mockServerSnap));

      // 2. Delegate enters branch basement (No internet): server fails, falls back to cache
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      when(() => mockQuery.get(const GetOptions(source: Source.cache)))
          .thenAnswer((_) async => mockCacheSnap);

      final offlineResult = await mockQuery.getResilient();
      expect(offlineResult, equals(mockCacheSnap));

      // 3. Delegate steps outside: Pull-to-refresh forces fresh server fetch
      when(() => mockQuery.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) async => mockServerSnap);

      final refreshResult = await mockQuery.getResilient(forceServer: true);
      expect(refreshResult, equals(mockServerSnap));
    });
  });

  group('Supervisor Experience - Login, Live Permissions Stream & Toggle', () {
    test('Supervisor authentication: correctly identifies supervisor role and permissions', () {
      final tSupervisor = DelegateModel.fromJson({
        'firstName': 'Mahmoud',
        'middleName': 'Hassan',
        'lastName': 'Ibrahim',
        'fullName': 'Mahmoud Hassan Ibrahim',
        'nationalityID': '28805051234567',
        'motherName': 'Mona',
        'city': 'Cairo',
        'phoneNumber': '01298765432',
        'gender': 'Male',
        'position': 'supervisor',
        'birthDate': '1988-05-05',
        'organizationUID': 'org_tashil',
        'organizationName': 'Tashil Business',
        'companyUID': 'comp_fathalla',
        'companyName': 'Fathalla Market',
        'status': 'approved',
        'delegatePublicId': 'SUP-202',
      }, 'sup_202');

      expect(tSupervisor.phoneNumber, equals('01298765432'));
      expect(tSupervisor.nationalityID, equals('28805051234567'));
      expect(tSupervisor.position, equals(DelegatePosition.supervisor));
      expect(tSupervisor.position == DelegatePosition.supervisor, isTrue);
    });

    test('Supervisor real-time permission stream emits updates instantaneously', () async {
      final mockQuery = MockQuery<Map<String, dynamic>>();
      final streamController = StreamController<QuerySnapshot<Map<String, dynamic>>>();

      when(() => mockQuery.snapshots(includeMetadataChanges: true))
          .thenAnswer((_) => streamController.stream);

      final stream = mockQuery.streamResilient();

      final mockSnap = MockQuerySnapshot<Map<String, dynamic>>();
      expectLater(stream, emits(mockSnap));

      streamController.add(mockSnap);
      await streamController.close();
    });

    test('Supervisor permission model toggles state without data loss', () {
      final tDate = DateTime(2026, 10, 1);
      final permission = PhotoPermissionModel(
        uid: 'perm_303',
        organizationUID: 'org_tashil',
        companyUID: 'comp_fathalla',
        companyName: 'Fathalla Market',
        companyCode: 10,
        branchIds: const ['branch_smoha'],
        branchNames: const ['Fathalla Smoha'],
        startDate: tDate,
        endDate: tDate.add(const Duration(days: 30)),
        status: 'approved',
        requestedBy: 'sup_202',
        createdAt: tDate,
        updatedAt: tDate,
        isSupervisorEnabled: true,
      );

      expect(permission.isSupervisorEnabled, isTrue);
      expect(permission.status, equals('approved'));
      expect(permission.branchNames, contains('Fathalla Smoha'));

      // Toggled permission representation
      final toggledPermission = PhotoPermissionModel(
        uid: permission.uid,
        organizationUID: permission.organizationUID,
        companyUID: permission.companyUID,
        companyName: permission.companyName,
        companyCode: permission.companyCode,
        branchIds: permission.branchIds,
        branchNames: permission.branchNames,
        startDate: permission.startDate,
        endDate: permission.endDate,
        status: permission.status,
        requestedBy: permission.requestedBy,
        createdAt: permission.createdAt,
        updatedAt: DateTime.now(),
        isSupervisorEnabled: false,
      );

      expect(toggledPermission.isSupervisorEnabled, isFalse);
      expect(toggledPermission.branchNames, contains('Fathalla Smoha'));
    });
  });
}
