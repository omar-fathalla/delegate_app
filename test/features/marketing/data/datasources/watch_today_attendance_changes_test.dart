// TAS-260: the branch home screen listens for attendance changes instead of
// polling every 30 seconds.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('branch query helpers', () {
    test('terms include the Arabic spelling variants', () {
      final terms = branchQueryTerms(['فرع أكتوبر', ' ', 'المعادى']);
      expect(terms, containsAll(['فرع أكتوبر', 'فرع اكتوبر', 'المعادى', 'المعادي']));
      expect(terms.contains(''), isFalse);
    });

    test('chunks stay within the whereIn limit', () {
      final chunks = branchQueryChunks(List.generate(45, (i) => 'b$i'));
      expect(chunks.map((c) => c.length), [20, 20, 5]);
      expect(branchQueryChunks(const []), isEmpty);
    });

    test('empty organization falls back to the default org', () {
      expect(attendanceQueryOrgId('  '), 'PiioBFgxaHAeuRdjlDgj');
      expect(attendanceQueryOrgId(' o1 '), 'o1');
    });
  });

  group('watchTodayAttendanceChanges', () {
    late FakeFirebaseFirestore db;
    late MarketingRemoteDataSourceImpl ds;
    final today = DateTime.now();

    Future<void> addLog(String id, String branch, {DateTime? at, String org = 'o1'}) =>
        db.collection(kAttendanceCollection).doc(id).set({
          'organizationId': org,
          'branchName': branch,
          'type': 'check_in',
          'delegateId': 'd-$id',
          'timestamp': Timestamp.fromDate(at ?? today),
        });

    setUp(() async {
      db = FakeFirebaseFirestore();
      ds = MarketingRemoteDataSourceImpl(firestore: db);
      await addLog('existing', 'Branch A');
    });

    test('no branches means no listener', () async {
      final events = <void>[];
      final sub = ds
          .watchTodayAttendanceChanges(branchNames: const [], organizationId: 'o1')
          .listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('skips the initial snapshot and emits on a new check-in', () async {
      var count = 0;
      final sub = ds
          .watchTodayAttendanceChanges(branchNames: const ['Branch A'], organizationId: 'o1', date: today)
          .listen((_) => count++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, 0, reason: 'the first snapshot is what the screen already loaded');

      await addLog('new', 'Branch A');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, 1);
      await sub.cancel();
    });

    test('ignores other branches, other orgs and other days', () async {
      var count = 0;
      final sub = ds
          .watchTodayAttendanceChanges(branchNames: const ['Branch A'], organizationId: 'o1', date: today)
          .listen((_) => count++);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await addLog('other-branch', 'Branch B');
      await addLog('other-org', 'Branch A', org: 'o2');
      await addLog('yesterday', 'Branch A', at: today.subtract(const Duration(days: 1)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, 0);
      await sub.cancel();
    });

    test('cancel stops further events', () async {
      var count = 0;
      final sub = ds
          .watchTodayAttendanceChanges(branchNames: const ['Branch A'], organizationId: 'o1', date: today)
          .listen((_) => count++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await addLog('after-cancel', 'Branch A');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, 0);
    });
  });
}
