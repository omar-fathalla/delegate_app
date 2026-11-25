// TAS-335: the branches screen finds today's attendance by branchId OR by
// name, so a log with a different spelling of the branch name is not missed.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:delegate_app/features/marketing/data/datasources/branch_attendance_query.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('pure helpers', () {
    test('favorites resolve to catalog ids by normalized name', () {
      final ids = resolveFavoriteBranchIds(
        ['الابراهيمية', 'سموحة', 'غير موجود'],
        [
          (id: 'br-ibr', name: 'الإبراهيميه'),
          (id: 'br-smo', name: 'سموحه'),
          (id: 'br-smo-dup', name: ' سموحة '),
          (id: '', name: 'سموحة'),
        ],
      );
      expect(ids['الابراهيمية'], {'br-ibr'});
      expect(ids['سموحة'], {'br-smo', 'br-smo-dup'});
      expect(ids['غير موجود'], isEmpty);
    });

    test('chunks keep ids + names <= 30 and a favorite in one chunk', () {
      final favorites = List.generate(12, (i) => 'b$i');
      final chunks = buildBranchAttendanceChunks(
        favorites: favorites,
        idsByFavorite: {
          for (final f in favorites) f: {'id-$f'},
        },
        nameTerms: (f) => {f, '$f-v1', '$f-v2'},
      );
      expect(
        chunks.every((c) => c.disjunctions <= kMaxAttendanceDisjunctions),
        isTrue,
      );
      expect(chunks.map((c) => c.disjunctions), [28, 20]);
      expect(chunks.first.branchIds, contains('id-b0'));
      expect(chunks.first.branchNames, containsAll(['b0', 'b0-v1', 'b0-v2']));
    });

    test('a log maps to its favorite by id first, then by name', () {
      final plan = BranchAttendancePlan.build(
        ['الابراهيمية', 'سموحة'],
        [(id: 'br-ibr', name: 'الابراهيمية')],
      );
      expect(
        plan.favoriteFor({'branchId': 'br-ibr', 'branchName': 'الإبراهيميه'}),
        'الابراهيمية',
      );
      expect(plan.favoriteFor({'branchName': 'سموحه'}), 'سموحة');
      expect(
        plan.favoriteFor({'branchId': 'other', 'branchName': 'مكان تاني'}),
        isNull,
      );
    });

    test('dedupe keeps the first copy of each document', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('x').doc('a').set({'v': 1});
      await db.collection('x').doc('b').set({'v': 2});
      final s = await db.collection('x').get();
      final out = dedupeAttendanceDocs([...s.docs, ...s.docs]);
      expect(out.map((d) => d.id), ['a', 'b']);
    });
  });

  group('getTodayAttendanceForBranches by branchId or name', () {
    late FakeFirebaseFirestore db;
    late MarketingRemoteDataSourceImpl ds;
    const org = 'org1';
    const favorite = 'الابراهيمية';
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    Future<void> log(String id, Map<String, dynamic> fields) =>
        db.collection(kAttendanceCollection).doc(id).set({
          'organizationId': org,
          'type': 'check_in',
          'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
          'delegateName': 'Delegate $id',
          'phoneNumber': '01000000000',
          ...fields,
        });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      DelegateProfileCache.clearSession();
      BranchesSessionCache.invalidate();
      BranchesSessionCache.debugSessionKey = () => 'test-user';
      db = FakeFirebaseFirestore();
      ds = MarketingRemoteDataSourceImpl(
        firestore: db,
        profileCache: DelegateProfileCache(prefs: prefs),
      );
      await db.collection('branches').doc('br-ibr').set({
        'branchName': favorite,
        'organizationUID': org,
      });
    });

    tearDown(() {
      BranchesSessionCache.debugSessionKey = null;
      BranchesSessionCache.invalidate();
    });

    test('finds a mixed-spelling log through its branchId', () async {
      // «الإبراهيميه» is none of the name variants of «الابراهيمية».
      expect(branchNameSpellings(favorite).contains('الإبراهيميه'), isFalse);
      await log('by-id', {
        'branchId': 'br-ibr',
        'branchName': 'الإبراهيميه',
        'delegateId': 'd1',
      });

      final res = await ds.getTodayAttendanceForBranches(
        branchNames: const [favorite],
        organizationId: org,
        date: today,
      );
      expect(res[favorite]!.map((r) => r['delegateId']), ['d1']);
    });

    test('legacy log without branchId is still found by name', () async {
      await log('legacy', {'branchName': 'الابراهيميه', 'delegateId': 'd2'});
      final res = await ds.getTodayAttendanceForBranches(
        branchNames: const [favorite],
        organizationId: org,
        date: today,
      );
      expect(res[favorite]!.map((r) => r['delegateId']), ['d2']);
    });

    test(
      'a log matching by id and by name is counted once; other orgs stay out',
      () async {
        await log('both', {
          'branchId': 'br-ibr',
          'branchName': favorite,
          'delegateId': 'd3',
        });
        await db.collection(kAttendanceCollection).doc('other-org').set({
          'organizationId': 'org2',
          'type': 'check_in',
          'branchId': 'br-ibr',
          'branchName': favorite,
          'delegateId': 'd4',
          'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
        });
        final res = await ds.getTodayAttendanceForBranches(
          branchNames: const [favorite],
          organizationId: org,
          date: today,
        );
        expect(res[favorite]!.map((r) => r['delegateId']), ['d3']);
      },
    );

    test(
      'the live listener also fires for a mixed-spelling check-in',
      () async {
        var events = 0;
        final sub = ds
            .watchTodayAttendanceChanges(
              branchNames: const [favorite],
              organizationId: org,
              date: today,
            )
            .listen((_) => events++);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await log('live', {
          'branchId': 'br-ibr',
          'branchName': 'الإبراهيميه',
          'delegateId': 'd5',
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(events, 1);
        await sub.cancel();
      },
    );
  });
}
