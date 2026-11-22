import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:test/test.dart';

/// hasPaidCoverage must accept the legacy 1.14.x subscription map (the only
/// shape on prod as of Nov 2026) as well as the new Paymob shape.
void main() {
  // 18 Nov 2026 12:00 Cairo (UTC+2) -> 2026_H2, free promotion active.
  final promoNow = DateTime.utc(2026, 11, 18, 10);
  // 20 Feb 2027 12:00 Cairo -> 2027_H1, free promotion over.
  final paidNow = DateTime.utc(2027, 2, 20, 10);

  Map<String, dynamic> legacy({
    String cycle = '2026_H2',
    Object? isPaid = true,
    String paymentMethod = 'freePromotion',
    Object? endDate = '2026-12-31T23:59:59.000',
  }) => {
    'startDate': '2026-07-01T00:00:00.000',
    'cycle': cycle,
    'isPaid': isPaid,
    'paymentMethod': paymentMethod,
    if (endDate != null) 'endDate': endDate,
    'approvedAt': '2026-11-01T19:05:32.441777',
    'approvedBy': 'Omar Fathalla',
  };

  bool covered(
    Map<String, dynamic>? sub, {
    required DateTime at,
    Map<String, dynamic>? next,
  }) => SubscriptionCycleHelper.hasPaidCoverage(
    sub,
    at: at,
    companyUID: 'WB076VvAgAsKMIQAZV8g',
    nextSubscription: next,
  );

  setUp(SubscriptionCycleHelper.resetConfigForTest);
  tearDown(SubscriptionCycleHelper.resetConfigForTest);

  group('legacy 1.14.x shape', () {
    test('prod sample (freePromotion, isPaid, 2026_H2) is covered', () {
      expect(covered(legacy(), at: promoNow), isTrue);
    });

    test('free_promotion spelling is covered during the promotion', () {
      expect(covered(legacy(paymentMethod: 'free_promotion'), at: promoNow), isTrue);
    });

    test('freePromotion without isPaid is still covered (waived)', () {
      expect(covered(legacy(isPaid: false), at: promoNow), isTrue);
    });

    test('freePromotion is not covered once the promotion ended', () {
      SubscriptionCycleHelper.applyConfig(freePromotionLastDay: '2026-11-01');
      expect(covered(legacy(), at: promoNow), isFalse);
    });

    test('branchReceipt / companyDeduction with isPaid are covered', () {
      expect(covered(legacy(paymentMethod: 'branchReceipt'), at: promoNow), isTrue);
      expect(covered(legacy(paymentMethod: 'companyDeduction'), at: promoNow), isTrue);
      SubscriptionCycleHelper.applyConfig(freePromotionLastDay: '2026-11-01');
      expect(covered(legacy(paymentMethod: 'branchReceipt'), at: promoNow), isTrue);
    });

    test('legacy unpaid (isPaid false / missing) is not covered', () {
      expect(covered(legacy(paymentMethod: 'branchReceipt', isPaid: false), at: promoNow), isFalse);
      expect(covered(legacy(paymentMethod: 'branchReceipt', isPaid: null), at: promoNow), isFalse);
      expect(covered(legacy(paymentMethod: 'branchReceipt', isPaid: 'true'), at: promoNow), isFalse);
    });

    test('wrong cycle is not covered', () {
      expect(covered(legacy(cycle: '2026_H1', endDate: null), at: promoNow), isFalse);
      expect(covered(legacy(cycle: '2027_H1', paymentMethod: 'branchReceipt', endDate: null), at: promoNow), isFalse);
      expect(covered(legacy(paymentMethod: 'branchReceipt'), at: paidNow), isFalse);
    });

    test('expired endDate is not covered', () {
      final m = legacy(paymentMethod: 'branchReceipt', endDate: '2026-11-17T23:59:59.000');
      expect(covered(m, at: promoNow), isFalse);
      // Zoned and DateTime forms.
      expect(covered(legacy(paymentMethod: 'branchReceipt', endDate: '2026-11-17T21:59:59Z'), at: promoNow), isFalse);
      expect(covered(legacy(paymentMethod: 'branchReceipt', endDate: DateTime.utc(2026, 11, 17)), at: promoNow), isFalse);
    });

    test('endDate later today (Cairo) is still covered', () {
      // 18 Nov 23:59:59 Cairo vs 12:00 Cairo now.
      expect(covered(legacy(endDate: '2026-11-18T23:59:59.000'), at: promoNow), isTrue);
    });

    test('31 Dec 23:59 Cairo covered, 1 Jan 2027 00:01 Cairo not', () {
      expect(covered(legacy(), at: DateTime.utc(2026, 12, 31, 21, 59)), isTrue);
      expect(covered(legacy(), at: DateTime.utc(2026, 12, 31, 22, 1)), isFalse);
    });

    test('garbage endDate is ignored', () {
      expect(covered(legacy(endDate: 'not-a-date'), at: promoNow), isTrue);
    });
  });

  group('missing / status-only', () {
    test('missing subscription is not covered', () {
      expect(covered(null, at: promoNow), isFalse);
      expect(covered(<String, dynamic>{}, at: promoNow), isFalse);
    });

    test('status active only is not covered', () {
      expect(covered({'status': 'active'}, at: promoNow), isFalse);
      expect(covered({'status': 'active', 'cycle': '2026_H2'}, at: promoNow), isFalse);
    });
  });

  group('new shape (unchanged)', () {
    test('paid in current period is covered', () {
      expect(covered({'paymentStatus': 'paid', 'periodCode': '2027_H1'}, at: paidNow), isTrue);
    });

    test('paid in another period is not covered', () {
      expect(covered({'paymentStatus': 'paid', 'periodCode': '2026_H2'}, at: paidNow), isFalse);
      expect(covered({'paymentStatus': 'paid', 'periodCode': '2027_H2'}, at: paidNow), isFalse);
    });

    test('waived covered only during the promotion', () {
      final w = {'paymentStatus': 'waived', 'periodCode': '2026_H2'};
      expect(covered(w, at: promoNow), isTrue);
      SubscriptionCycleHelper.applyConfig(freePromotionLastDay: '2026-11-01');
      expect(covered(w, at: promoNow), isFalse);
    });

    test('pending / failed are not covered, legacy fields ignored', () {
      expect(covered({'paymentStatus': 'pending', 'periodCode': '2027_H1', 'isPaid': true}, at: paidNow), isFalse);
      expect(covered({'paymentStatus': 'failed', 'periodCode': '2027_H1'}, at: paidNow), isFalse);
    });

    test('missing period is not covered', () {
      expect(covered({'paymentStatus': 'paid'}, at: paidNow), isFalse);
    });
  });

  group('nextSubscription', () {
    test('legacy next map for the current period counts', () {
      expect(covered(null, at: paidNow, next: legacy(cycle: '2027_H1', paymentMethod: 'branchReceipt', endDate: '2027-06-30T23:59:59.000')), isTrue);
    });

    test('next map for a future period does not count as current', () {
      expect(covered(legacy(paymentMethod: 'branchReceipt', isPaid: false), at: promoNow, next: legacy(cycle: '2027_H1', paymentMethod: 'branchReceipt', endDate: null)), isFalse);
      expect(covered(null, at: promoNow, next: {'paymentStatus': 'paid', 'periodCode': '2027_H1'}), isFalse);
    });
  });
}
