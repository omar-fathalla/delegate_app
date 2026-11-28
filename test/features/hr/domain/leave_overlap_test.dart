import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/hr/domain/leave_overlap.dart';
import 'package:flutter_test/flutter_test.dart';

// TAS-370: overlap check (L-1) and the backdate limit (L-2).
LeaveSpan span(
  String id,
  DateTime start,
  DateTime end, {
  String status = 'pending',
  String type = 'annual',
  bool hourly = false,
}) => LeaveSpan(
  id: id,
  type: type,
  isHourly: hourly,
  status: status,
  start: start,
  end: end,
);

void main() {
  final d1 = DateTime(2026, 12, 1);
  final d3 = DateTime(2026, 12, 3);
  final d4 = DateTime(2026, 12, 4);
  final d6 = DateTime(2026, 12, 6);

  group('LeaveOverlap.find', () {
    test('shared days overlap; touching but separate days do not', () {
      final cand = span('new', d3, d6);
      expect(LeaveOverlap.find(cand, [span('a', d1, d3)])?.id, 'a');
      expect(
        LeaveOverlap.find(cand, [span('a', d1, DateTime(2026, 12, 2))]),
        isNull,
      );
    });

    test('rejected requests never count', () {
      final cand = span('new', d1, d4);
      expect(
        LeaveOverlap.find(cand, [span('a', d1, d4, status: 'rejected')]),
        isNull,
      );
    });

    test('an approved conflict wins over a pending one', () {
      final cand = span('new', d1, d6);
      final hit = LeaveOverlap.find(cand, [
        span('p', d1, d1),
        span('ok', d4, d4, status: 'approved'),
      ]);
      expect(hit?.id, 'ok');
      expect(hit?.isApproved, isTrue);
    });

    test('the request itself is skipped (HR approving it)', () {
      final cand = span('same', d1, d4);
      expect(LeaveOverlap.find(cand, [span('same', d1, d4)]), isNull);
    });

    test(
      'two hourly excuses on one day are fine; inside a leave they are not',
      () {
        final late = span('new', d3, d3, type: 'delay', hourly: true);
        expect(
          LeaveOverlap.find(late, [
            span('e', d3, d3, type: 'early_leave', hourly: true),
          ]),
          isNull,
        );
        expect(LeaveOverlap.find(late, [span('a', d1, d4)])?.id, 'a');
      },
    );

    test('fromMap reads Firestore timestamps by day and fixes end < start', () {
      final s = LeaveSpan.fromMap('x', {
        'startDate': Timestamp.fromDate(DateTime(2026, 12, 3, 15)),
        'endDate': Timestamp.fromDate(DateTime(2026, 12, 1)),
        'status': 'approved',
        'type': 'sick',
      })!;
      expect(s.start, d3);
      expect(s.end, d3);
      expect(s.isApproved, isTrue);
      expect(LeaveSpan.fromMap('y', {'status': 'pending'}), isNull);
    });
  });

  group('LeaveBackdate (user decision 2026-11-27)', () {
    final today = DateTime(2026, 11, 28, 14, 30);
    test('sick, emergency, absence 7 days; annual and unpaid today', () {
      for (final t in ['sick', 'emergency', 'absence']) {
        expect(
          LeaveBackdate.firstDate(today, t, isHourly: false),
          DateTime(2026, 11, 21),
        );
      }
      for (final t in ['annual', 'unpaid']) {
        expect(
          LeaveBackdate.firstDate(today, t, isHourly: false),
          DateTime(2026, 11, 28),
        );
      }
    });
    test('hourly excuses keep 30 days', () {
      expect(LeaveBackdate.daysFor('delay', isHourly: true), 30);
    });
  });
}
