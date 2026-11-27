import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-362: a forgotten session counts zero until HR sets the check-out,
/// only from the configured start date (not retroactive).
void main() {
  final ruleFrom = DateTime(2026, 11, 28);
  final now = DateTime(2026, 12, 2, 12);

  tearDown(MissingCheckOutRule.debugReset);

  int paid({
    required DateTime checkIn,
    DateTime? checkOut,
    bool flagged = false,
    bool adjusted = false,
    DateTime? from,
  }) =>
      PayrollDayRules.paidMinutesForDay(
        checkIn: checkIn,
        checkOut: checkOut,
        now: now,
        shiftHours: 9,
        forgottenFlag: flagged,
        manuallyAdjusted: adjusted,
        missingCheckOutRuleFrom: from,
      );

  group('payroll', () {
    test('no check-out after 11.5 h: zero from the rule date', () {
      expect(paid(checkIn: DateTime(2026, 12, 1, 9), from: ruleFrom), 0);
    });

    test('before the rule date: old full shift (not retroactive)', () {
      expect(paid(checkIn: DateTime(2026, 11, 27, 9), from: ruleFrom), 540);
    });

    test('rule off (no date): old full shift', () {
      expect(paid(checkIn: DateTime(2026, 12, 1, 9)), 540);
    });

    test('auto check-out record (old app) counts zero even with a check-out time', () {
      expect(
        paid(
          checkIn: DateTime(2026, 12, 1, 9),
          checkOut: DateTime(2026, 12, 1, 20, 30),
          flagged: true,
          from: ruleFrom,
        ),
        0,
      );
    });

    test('HR set the check-out by hand: counted again', () {
      expect(
        paid(
          checkIn: DateTime(2026, 12, 1, 9),
          checkOut: DateTime(2026, 12, 1, 17),
          flagged: true,
          adjusted: true,
          from: ruleFrom,
        ),
        480,
      );
    });

    test('a shift crossing midnight is not forgotten before 11.5 h', () {
      final lateNow = DateTime(2026, 12, 2, 2);
      expect(
        PayrollDayRules.paidMinutesForDay(
          checkIn: DateTime(2026, 12, 1, 20),
          now: lateNow,
          shiftHours: 9,
          missingCheckOutRuleFrom: ruleFrom,
        ),
        0,
        reason: 'still ongoing: nothing paid yet, but not flagged as forgotten',
      );
      expect(
        MissingCheckOutRule.isUnpaid(
          checkIn: DateTime(2026, 12, 1, 20),
          flagged: false,
          now: lateNow,
          ruleFrom: ruleFrom,
        ),
        isFalse,
      );
    });

    test('a normal session is unchanged', () {
      expect(
        paid(checkIn: DateTime(2026, 12, 1, 9), checkOut: DateTime(2026, 12, 1, 16), from: ruleFrom),
        420,
      );
    });
  });

  group('record helpers', () {
    test('flags on the check-in or the check-out record', () {
      expect(MissingCheckOutRule.flaggedIn([{'missingCheckOut': true}, null]), isTrue);
      expect(MissingCheckOutRule.flaggedIn([{}, {'isAutoCheckOut': true}]), isTrue);
      expect(MissingCheckOutRule.flaggedIn([{}, {}]), isFalse);
      expect(MissingCheckOutRule.adjustedIn([{}, {'isManuallyAdjusted': true}]), isTrue);
    });
  });

  group('delegate history (Attendance entity)', () {
    Attendance session({DateTime? out, bool auto = false}) => Attendance(
          id: 'a',
          userId: 'u',
          organizationId: 'o',
          checkInTime: DateTime.now().subtract(const Duration(hours: 13)),
          checkOutTime: out,
          isAutoCheckOut: auto,
        );

    test('forgotten session: no effective check-out, not active', () {
      MissingCheckOutRule.debugSet(DateTime(2020));
      final s = session();
      expect(s.isMissingCheckOut, isTrue);
      expect(s.effectiveCheckOutTime, isNull);
      expect(s.isActive, isFalse);
      // Auto-closed by an old build: still zero.
      expect(session(out: DateTime.now(), auto: true).effectiveCheckOutTime, isNull);
    });

    test('rule off: the old +11.5 h display', () {
      MissingCheckOutRule.debugSet(null);
      expect(session().effectiveCheckOutTime, isNotNull);
    });
  });

  test('ensureLoaded reads system_config/attendance_rules once; missing doc = off', () async {
    final fs = FakeFirebaseFirestore();
    await MissingCheckOutRule.ensureLoaded(fs);
    expect(MissingCheckOutRule.from, isNull);

    MissingCheckOutRule.debugReset();
    await fs.doc(MissingCheckOutRule.configPath).set({
      MissingCheckOutRule.fromField: Timestamp.fromDate(ruleFrom),
    });
    await MissingCheckOutRule.ensureLoaded(fs);
    expect(MissingCheckOutRule.from, ruleFrom);
  });
}
