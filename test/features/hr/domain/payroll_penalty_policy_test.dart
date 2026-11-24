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
}
