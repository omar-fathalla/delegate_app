import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/monthly_attendance_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Attendance _s(DateTime inT, [DateTime? outT]) => Attendance(
  id: inT.toIso8601String(),
  userId: 'u',
  organizationId: 'o',
  checkInTime: inT,
  checkOutTime: outT,
);

void main() {
  final oct = DateTime(2026, 10);
  // Real October 2026 pattern from the reported case (24 attended days).
  const attended = [
    1,
    2,
    4,
    5,
    6,
    8,
    9,
    11,
    12,
    13,
    15,
    16,
    18,
    19,
    20,
    22,
    23,
    24,
    25,
    26,
    27,
    29,
    30,
    31,
  ];
  List<Attendance> octSessions() => [
    for (final d in attended)
      _s(DateTime(2026, 10, d, 11), DateTime(2026, 10, d, 17)),
    // Two sessions on the same day count once.
    _s(DateTime(2026, 10, 25, 14), DateTime(2026, 10, 25, 17)),
    _s(DateTime(2026, 10, 26, 13), DateTime(2026, 10, 26, 15)),
  ];

  test('>20 sessions: whole month gives 24 present / 2 absent', () {
    final sessions = octSessions();
    expect(sessions.length, greaterThan(20));
    final st = MonthlyAttendanceStats.compute(
      sessions: sessions,
      month: oct,
      now: DateTime(2026, 11, 2, 9),
      createdAt: DateTime(2025, 1, 1),
    );
    expect(st.presentDays, 24);
    expect(st.absentDays, 2);
  });

  test(
    'home (current month on 31 Oct) and attendance tab (past month) agree',
    () {
      final home = MonthlyAttendanceStats.compute(
        sessions: octSessions(),
        month: DateTime(2026, 10, 31, 13, 56),
        now: DateTime(2026, 10, 31, 13, 56),
        createdAt: DateTime(2025, 1, 1),
      );
      final tab = MonthlyAttendanceStats.compute(
        sessions: octSessions(),
        month: oct,
        now: DateTime(2026, 11, 1, 16, 53),
        createdAt: DateTime(2025, 1, 1),
      );
      expect(home.presentDays, tab.presentDays);
      expect(home.absentDays, tab.absentDays);
    },
  );

  test('current month counts elapsed days only', () {
    final st = MonthlyAttendanceStats.compute(
      sessions: [for (var d = 1; d <= 8; d++) _s(DateTime(2026, 10, d, 10))],
      month: oct,
      now: DateTime(2026, 10, 10, 12),
    );
    // 10 days - 1 off day = 9 expected, 8 present.
    expect(st.expectedWorkDays, 9);
    expect(st.absentDays, 1);
  });

  test('past month uses the full month and subtracts approved leave', () {
    final st = MonthlyAttendanceStats.compute(
      sessions: [for (var d = 1; d <= 20; d++) _s(DateTime(2026, 9, d, 10))],
      month: DateTime(2026, 9),
      now: DateTime(2026, 10, 5),
      approvedLeaveDays: 2,
    );
    expect(st.expectedWorkDays, 24);
    expect(st.absentDays, 4);
    expect(st.leaveDays, 2);
  });

  test('future month and before registration give zero absence', () {
    expect(
      MonthlyAttendanceStats.compute(
        sessions: const [],
        month: DateTime(2026, 12),
        now: DateTime(2026, 11, 2),
      ).absentDays,
      0,
    );
    expect(
      MonthlyAttendanceStats.compute(
        sessions: const [],
        month: DateTime(2026, 9),
        now: DateTime(2026, 11, 2),
        createdAt: DateTime(2026, 10, 15),
      ).absentDays,
      0,
    );
  });

  test('mid-month registration only counts days since joining', () {
    final st = MonthlyAttendanceStats.compute(
      sessions: [_s(DateTime(2026, 10, 20, 10))],
      month: oct,
      now: DateTime(2026, 10, 21, 10),
      createdAt: DateTime(2026, 10, 15),
    );
    // 7 active days - 1 off = 6 expected, 1 present.
    expect(st.absentDays, 5);
  });

  test('overnight session counts once, on its check-in day', () {
    final st = MonthlyAttendanceStats.compute(
      sessions: [
        _s(DateTime(2026, 10, 27, 12, 3), DateTime(2026, 10, 28, 20, 38)),
        _s(DateTime(2026, 10, 31, 22), DateTime(2026, 11, 1, 4)),
      ],
      month: oct,
      now: DateTime(2026, 11, 2),
    );
    expect(st.presentDayKeys, ['2026-10-27', '2026-10-31']);
    final nov = MonthlyAttendanceStats.compute(
      sessions: [_s(DateTime(2026, 10, 31, 22), DateTime(2026, 11, 1, 4))],
      month: DateTime(2026, 11),
      now: DateTime(2026, 11, 2),
    );
    expect(nov.presentDays, 0);
  });

  // TAS-379: the two cases reported from the store build (v1.14.2), where the
  // attendance tab counted the loaded history page only. The whole month
  // must give the same numbers as the home card.
  group('TAS-379 reported cases (November 2026)', () {
    final nov = DateTime(2026, 11);

    test('Arzaq: 21 days on one branch, on 26 Nov: 21 present, 2 absent', () {
      const days = [
        1, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, //
        17, 18, 19, 20, 21, 22, 24, 25, 26,
      ];
      final st = MonthlyAttendanceStats.compute(
        sessions: [
          for (final d in days)
            _s(DateTime(2026, 11, d, 9), DateTime(2026, 11, d, 17)),
        ],
        month: nov,
        now: DateTime(2026, 11, 26, 18),
        createdAt: DateTime(2025, 1, 1),
      );
      expect(st.presentDays, 21);
      expect(st.absentDays, 2);
    });

    test(
      'Dunia: 3 branches a day and a 10→12 Nov session, on 28 Nov: '
      '21 present, 3 absent',
      () {
        // Days with a check-in; 4-7, 11, 18 and 25 have none (11 is inside
        // the session that started on the 10th and ended on the 12th).
        const days = [
          1, 2, 3, 8, 9, 10, 12, 13, 14, 15, 16, //
          17, 19, 20, 21, 22, 23, 24, 26, 27, 28,
        ];
        final sessions = <Attendance>[
          for (final d in days)
            if (d != 10) ...[
              // Three branches the same day count as one day.
              _s(DateTime(2026, 11, d, 9), DateTime(2026, 11, d, 11)),
              _s(DateTime(2026, 11, d, 12), DateTime(2026, 11, d, 14)),
              _s(DateTime(2026, 11, d, 15), DateTime(2026, 11, d, 18)),
            ],
          _s(DateTime(2026, 11, 10, 10, 40), DateTime(2026, 11, 12, 9)),
        ];
        // More sessions than one history page ever held.
        expect(sessions.length, greaterThan(60));
        final st = MonthlyAttendanceStats.compute(
          sessions: sessions,
          month: nov,
          now: DateTime(2026, 11, 28, 20),
          createdAt: DateTime(2025, 1, 1),
        );
        expect(st.presentDays, 21);
        expect(st.presentDayKeys, isNot(contains('2026-11-11')));
        expect(st.absentDays, 3);
      },
    );
  });
}
