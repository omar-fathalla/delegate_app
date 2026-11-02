import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/config/read_reduction_flags.dart';
import 'package:delegate_app/core/services/badge_counts_service.dart';
import 'package:delegate_app/core/utils/branch_key.dart';
import 'package:delegate_app/features/marketing/data/datasources/today_attendance_query.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_live_refresh_controller.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _coll = 'attendance_logs_test_rr2';

void main() {
  group('#1 legacy query always runs until backfilled', () {
    late FakeFirebaseFirestore db;
    final dayStart = DateTime(2026, 11, 3);

    Future<void> seed(String id, String branch, {bool withKey = true}) =>
        db.collection(_coll).doc(id).set({
          'organizationId': 'org1',
          'branchName': branch,
          if (withKey) 'branchKey': branchKey(branch),
          'timestamp': Timestamp.fromDate(DateTime(2026, 11, 3, 9)),
        });

    Future<TodayAttendanceFetch> fetch(ReadReductionFlags flags) =>
        fetchTodayAttendanceDocs(
          firestore: db,
          branchNames: const ['فرع الدقي'],
          organizationId: 'org1',
          dayStart: dayStart,
          dayEnd: dayStart.add(const Duration(days: 1)),
          flags: flags,
          collection: _coll,
        );

    setUp(() async {
      db = FakeFirebaseFirestore();
      // Same branch, same day: one new-app (keyed) and one old-app record.
      await seed('newApp', 'فرع الدقي');
      await seed('oldApp', 'فرع الدقي', withKey: false);
    });

    test('mixed branch returns keyed AND unkeyed docs, merged by id', () async {
      final r = await fetch(ReadReductionFlags.fixed());
      expect(r.docs.map((d) => d.id).toList()..sort(), ['newApp', 'oldApp']);
      expect(r.legacyBranches, {'فرع الدقي'});
      // Pre-backfill: only the legacy query (it already covers keyed docs).
      expect(r.queries, 1);
    });

    test('backfilled flag drops the legacy query', () async {
      final r = await fetch(
        ReadReductionFlags.fixed({
          ReadReductionFlags.branchKeyBackfilledKey: true,
        }),
      );
      expect(r.docs.map((d) => d.id), ['newApp']);
      expect(r.queries, 1);
    });
  });

  group('#2/#3 BranchLiveRefreshController', () {
    late StreamController<int> source;
    late List<bool> reloads;
    late int midnights;
    late bool backfilled;
    late DateTime now;

    BranchLiveRefreshController make() => BranchLiveRefreshController(
      watch: () => source.stream,
      onReload: ({required bool force}) => reloads.add(force),
      onMidnight: () => midnights++,
      branchKeyBackfilled: () => backfilled,
      clock: () => now,
    );

    setUp(() {
      source = StreamController<int>.broadcast();
      reloads = [];
      midnights = 0;
      backfilled = true;
      now = DateTime(2026, 11, 3, 12);
    });

    testWidgets('debounces change bursts into one forced reload (10 s)', (
      tester,
    ) async {
      final c = make()..start();
      source
        ..add(1)
        ..add(2);
      await tester.pump(const Duration(seconds: 5));
      source.add(1);
      await tester.pump(const Duration(seconds: 9));
      expect(reloads, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(reloads, [true]);
      c.stop();
    });

    testWidgets('listener error falls back to a 3 min forced poll', (
      tester,
    ) async {
      final c = make()..start();
      source.addError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
        ),
      );
      await tester.pump();
      expect(c.inErrorFallback, isTrue);
      await tester.pump(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));
      expect(reloads, [true, true]);
      c.stop();
      await tester.pump(const Duration(minutes: 10));
      expect(reloads, hasLength(2), reason: 'stop() cancels the poll');
    });

    testWidgets('safety-net 5 min non-forced refresh only until backfilled', (
      tester,
    ) async {
      backfilled = false;
      final c = make()..start();
      expect(c.hasSafetyNet, isTrue);
      await tester.pump(const Duration(minutes: 5));
      expect(reloads, [false]);
      c.stop();

      backfilled = true;
      reloads.clear();
      final c2 = make()..start();
      expect(c2.hasSafetyNet, isFalse);
      await tester.pump(const Duration(minutes: 11));
      expect(reloads, isEmpty);
      c2.stop();
    });

    testWidgets('fires once at next local midnight, then reschedules', (
      tester,
    ) async {
      now = DateTime(2026, 11, 3, 23, 59, 0);
      final c = make()..start();
      await tester.pump(const Duration(seconds: 59));
      expect(midnights, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(midnights, 1);
      expect(c.isRunning, isTrue, reason: 'rescheduled for the next day');
      now = DateTime(2026, 11, 4, 0, 0, 1);
      c.stop();
      expect(c.isRunning, isFalse);
      await tester.pump(const Duration(days: 1));
      expect(midnights, 1, reason: 'cancelled when stopped/not visible');
    });

    test('untilNextMidnight', () {
      expect(
        BranchLiveRefreshController.untilNextMidnight(
          DateTime(2026, 11, 3, 22),
        ),
        const Duration(hours: 2),
      );
    });
  });

  test('badge invalidate discards a stale in-flight count', () async {
    final pending = <Completer<int?>>[];
    final svc = BadgeCountsService(
      loader: (_) {
        final c = Completer<int?>();
        pending.add(c);
        return c.future;
      },
    );
    final values = <int>[];
    final sub = svc.watch('leave_requests', 'c1').listen(values.add);
    await pumpEventQueue();
    expect(pending, hasLength(1));
    final forced = svc.invalidateCollection('leave_requests');
    await pumpEventQueue();
    expect(pending, hasLength(2));
    pending[1].complete(2); // fresh result (after approve)
    await forced;
    pending[0].complete(5); // stale result lands late
    await pumpEventQueue();
    expect(svc.notifier(const BadgeCountKey('leave_requests', 'c1')).value, 2);
    expect(values.last, 2);
    await sub.cancel();
    svc.debugReset();
  });
}
