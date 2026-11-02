
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/config/read_reduction_flags.dart';
import 'package:delegate_app/core/services/badge_counts_service.dart';
import 'package:delegate_app/core/utils/branch_key.dart';
import 'package:delegate_app/features/marketing/data/datasources/today_attendance_query.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _coll = 'attendance_logs_test_rr';

void main() {
  group('branchKey', () {
    test('normalizes spelling variants to one key', () {
      const variants = ['فرع  المعادى', ' فرع المعادي ', 'فرع المعادي'];
      final keys = variants.map(branchKey).toSet();
      expect(keys, hasLength(1));
      expect(branchKey('مكتبة'), branchKey('مكتبه'));
      expect(branchKey('أسيوط'), branchKey('اسيوط'));
      expect(branchKey('إمبابة'), branchKey('امبابه'));
      expect(branchKey('Nasr City'), 'nasr city');
    });

    test('branchKeyField skips empty/null', () {
      expect(branchKeyField(null), isEmpty);
      expect(branchKeyField('  '), isEmpty);
      expect(branchKeyField('فرع ة'), {'branchKey': branchKey('فرع ة')});
    });
  });

  group('fetchTodayAttendanceDocs', () {
    late FakeFirebaseFirestore db;
    final dayStart = DateTime(2026, 11, 3);
    final dayEnd = DateTime(2026, 11, 4);

    Future<void> seed(
      String id,
      String branch,
      DateTime ts, {
      bool withKey = true,
      String org = 'org1',
    }) {
      return db.collection(_coll).doc(id).set({
        'organizationId': org,
        'branchName': branch,
        if (withKey) 'branchKey': branchKey(branch),
        'timestamp': Timestamp.fromDate(ts),
        'type': 'check_in',
      });
    }

    Future<Set<String>> ids(
      ReadReductionFlags flags, {
      List<String> branches = const ['فرع المعادي', 'فرع الدقي'],
    }) async {
      final r = await fetchTodayAttendanceDocs(
        firestore: db,
        branchNames: branches,
        organizationId: 'org1',
        dayStart: dayStart,
        dayEnd: dayEnd,
        flags: flags,
        collection: _coll,
      );
      return r.docs.map((d) => d.id).toSet();
    }

    setUp(() async {
      db = FakeFirebaseFirestore();
      await seed('a', 'فرع المعادى', DateTime(2026, 11, 3, 9));
      await seed('b', 'فرع الدقي', DateTime(2026, 11, 3, 10));
      await seed('yesterday', 'فرع الدقي', DateTime(2026, 11, 2, 10));
      await seed(
        'otherOrg',
        'فرع الدقي',
        DateTime(2026, 11, 3, 10),
        org: 'org2',
      );
      await seed('otherBranch', 'فرع الزمالك', DateTime(2026, 11, 3, 10));
    });

    test(
      'branchKey query matches legacy query and excludes yesterday',
      () async {
        final keyed = await ids(ReadReductionFlags.fixed());
        final legacy = await ids(
          ReadReductionFlags.fixed({
            ReadReductionFlags.useBranchKeyQueryKey: false,
          }),
        );
        expect(keyed, {'a', 'b'});
        // Legacy variants never matched a stored 'ى' spelling when the branch
      // is configured with 'ي'; branchKey does. Otherwise identical.
      expect(legacy, {'b'});
      expect(keyed.containsAll(legacy), isTrue);
      },
    );

    test('falls back to branchName for old docs without branchKey', () async {
      db = FakeFirebaseFirestore();
      await seed('old', 'فرع الدقي', DateTime(2026, 11, 3, 8), withKey: false);
      await seed('new', 'فرع المعادي', DateTime(2026, 11, 3, 8));
      final r = await fetchTodayAttendanceDocs(
        firestore: db,
        branchNames: const ['فرع المعادي', 'فرع الدقي'],
        organizationId: 'org1',
        dayStart: dayStart,
        dayEnd: dayEnd,
        flags: ReadReductionFlags.fixed(),
        collection: _coll,
      );
      expect(r.docs.map((d) => d.id).toSet(), {'old', 'new'});
      expect(r.legacyBranches, {'فرع الدقي'});
    });

    test('no fallback once backfill flag is on', () async {
      db = FakeFirebaseFirestore();
      await seed('old', 'فرع الدقي', DateTime(2026, 11, 3, 8), withKey: false);
      final got = await ids(
        ReadReductionFlags.fixed({
          ReadReductionFlags.branchKeyBackfilledKey: true,
        }),
      );
      expect(got, isEmpty);
    });

    test('chunks more than 20 branches', () async {
      final many = [for (var i = 0; i < 45; i++) 'branch $i'];
      await seed('b44', 'branch 44', DateTime(2026, 11, 3, 8));
      final r = await fetchTodayAttendanceDocs(
        firestore: db,
        branchNames: many,
        organizationId: 'org1',
        dayStart: dayStart,
        dayEnd: dayEnd,
        flags: ReadReductionFlags.fixed({
          ReadReductionFlags.branchKeyBackfilledKey: true,
        }),
        collection: _coll,
      );
      expect(r.docs.map((d) => d.id), ['b44']);
      expect(r.queries, 3);
      expect(chunkList(many, kBranchWhereInChunkSize).length, 3);
    });
  });

  group('shouldSendTrackingPing', () {
    final now = DateTime(2026, 11, 3, 12);
    test('first ping always sends', () {
      expect(
        shouldSendTrackingPing(movedMeters: null, lastSentAt: null, now: now),
        isTrue,
      );
    });
    test('skips small moves within interval', () {
      expect(
        shouldSendTrackingPing(
          movedMeters: 5,
          lastSentAt: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isFalse,
      );
    });
    test('sends on big move or elapsed interval', () {
      expect(
        shouldSendTrackingPing(
          movedMeters: 80,
          lastSentAt: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldSendTrackingPing(
          movedMeters: 1,
          lastSentAt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('BadgeCountsService', () {
    test('shares and throttles loads, forces on invalidate', () async {
      var calls = 0;
      var t = DateTime(2026, 11, 3, 12);
      final svc = BadgeCountsService(
        loader: (_) async => ++calls,
        clock: () => t,
        minInterval: const Duration(hours: 1),
      );
      final a = <int>[];
      final s1 = svc.watch('leave_requests', 'c1').listen(a.add);
      final s2 = svc.watch('leave_requests', 'c1').listen((_) {});
      await pumpEventQueue();
      expect(calls, 1);
      expect(a.last, 1);
      t = t.add(const Duration(minutes: 1));
      final s3 = svc.watch('leave_requests', 'c1').listen((_) {});
      await pumpEventQueue();
      expect(calls, 1, reason: 'throttled');
      await svc.invalidate('leave_requests', 'c1');
      expect(calls, 2);
      await pumpEventQueue();
      expect(a.last, 2);
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
      svc.debugReset();
    });
  });

  testWidgets('lazy M3FadeThroughIndexedStack builds only visited tabs', (
    tester,
  ) async {
    final built = <int>{};
    Widget tab(int i) => Builder(
      builder: (_) {
        built.add(i);
        return Text('tab $i');
      },
    );
    Widget app(int index) => MaterialApp(
      home: M3FadeThroughIndexedStack(
        index: index,
        lazy: true,
        children: [tab(0), tab(1), tab(2)],
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(built, {0});
    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();
    expect(built, {0, 2});
  });
}
