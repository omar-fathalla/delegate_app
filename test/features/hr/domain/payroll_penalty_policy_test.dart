import 'package:delegate_app/features/hr/domain/payroll_penalty_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPayrollDeductiblePenaltyStatus (TAS-308)', () {
    test('issued, acknowledged and deducted penalties are deducted', () {
      for (final s in ['ISSUED', 'ACKNOWLEDGED', 'DEDUCTED', 'issued']) {
        expect(isPayrollDeductiblePenaltyStatus(s), isTrue, reason: s);
      }
    });
    test('legacy approved / applied still count', () {
      expect(isPayrollDeductiblePenaltyStatus('approved'), isTrue);
      expect(isPayrollDeductiblePenaltyStatus('applied'), isTrue);
    });
    test('pending, rejected, disputed, cancelled and empty do not', () {
      for (final s in [
        'PENDING_BRANCHES_MARKETING',
        'PENDING_GENERAL_MANAGER',
        'REJECTED_BRANCHES_MARKETING',
        'REJECTED_GENERAL_MANAGER',
        'DISPUTED',
        'CANCELLED',
        '',
        null,
      ]) {
        expect(isPayrollDeductiblePenaltyStatus(s), isFalse, reason: '$s');
      }
    });
  });

  group('isPenaltyInPayrollMonth (TAS-365)', () {
    test('no deductionMonth: the createdAt month', () {
      final d = {'createdAt': DateTime(2026, 11, 20)};
      expect(isPenaltyInPayrollMonth(d, year: 2026, month: 11), isTrue);
      expect(isPenaltyInPayrollMonth(d, year: 2026, month: 12), isFalse);
    });
    test('upheld after a dispute: the decision month, not the creation month', () {
      final d = {'createdAt': DateTime(2026, 11, 29), 'deductionMonth': '2026-12'};
      expect(isPenaltyInPayrollMonth(d, year: 2026, month: 12), isTrue);
      expect(isPenaltyInPayrollMonth(d, year: 2026, month: 11), isFalse);
    });
    test('a disputed penalty is never deducted while open', () {
      expect(isPayrollDeductiblePenaltyStatus('DISPUTED'), isFalse);
    });
    test('bad deductionMonth falls back to createdAt; no date counts', () {
      final d = {'createdAt': DateTime(2026, 11, 2), 'deductionMonth': 'x'};
      expect(isPenaltyInPayrollMonth(d, year: 2026, month: 11), isTrue);
      expect(isPenaltyInPayrollMonth(const {}, year: 2026, month: 11), isTrue);
    });
  });
}
